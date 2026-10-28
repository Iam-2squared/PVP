# CI-only regression for Quick Tunnel URL scanning while logfile is held open.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Tunnel-Log.ps1")

$dir = Join-Path ([IO.Path]::GetTempPath()) ("pvp-tunnel-qa-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $dir -Force | Out-Null
try {
    $log = Join-Path $dir "cloudflared-live.log"
    $expected = "https://quiet-marble-otter.trycloudflare.com"
    $lines = @(
        "Thank you for trying Cloudflare Tunnel.",
        "Requesting new quick Tunnel on trycloudflare.com...",
        "Your quick Tunnel has been created!"
        " | " + $expected + " | "
    )
    for ($i=0; $i -lt 70; $i++) { $lines += ("connectivity precheck row " + $i) }
    $lines += "Registered tunnel connection connIndex=0 protocol=quic"
    [IO.File]::WriteAllText($log, ($lines -join [Environment]::NewLine), [Text.Encoding]::UTF8)
    if ((Get-PvpTunnelUrl @($log)) -ne $expected) {
        throw "A valid URL emitted early in a long log was not detected."
    }

    # Simulate cloudflared's own logfile with an active, shared writer.
    $stream = [IO.FileStream]::new($log, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    try {
        if ((Get-PvpTunnelUrl @($log)) -ne $expected) {
            throw "Live logfile could not be read with an active shared writer."
        }
    } finally { $stream.Dispose() }

    # The redirected stderr stream may be locked, so the live logfile must
    # remain a usable first source even when a fallback source cannot be read.
    $locked = Join-Path $dir "stderr-locked.log"
    $exclusive = [IO.FileStream]::new($locked, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        if ((Get-PvpTunnelUrl @($locked,$log)) -ne $expected) {
            throw "Locked redirected output prevented reading the independent logfile."
        }
    } finally { $exclusive.Dispose() }

    $wrong = Join-Path $dir "wrong.log"
    [IO.File]::WriteAllText($wrong, "https://example.com" + [Environment]::NewLine + "trycloudflare.com without a URL")
    if (-not [string]::IsNullOrEmpty((Get-PvpTunnelUrl @($wrong)))) {
        throw "Unrelated URL was accepted as a Cloudflare Quick Tunnel."
    }

    Write-Host "PVP_TUNNEL_LOG_TEST_RESULT PASS"
} finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}
