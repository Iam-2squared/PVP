# CI-only, does not touch player saves. Spawns two disposable PowerShell processes
# and validates that the stop script unwraps a legacy nested JSON array.
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$directory = Join-Path $root ".pvp-local"
$state = Join-Path $directory "processes.json"
New-Item -ItemType Directory -Force -Path $directory | Out-Null
if (Test-Path -LiteralPath $state) { throw "Refusing to overwrite a running user's process registry." }

$spawned = @()
try {
    for ($i=0; $i -lt 2; $i++) {
        $child = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile","-NonInteractive","-Command","Start-Sleep -Seconds 120") -WindowStyle Hidden -PassThru
        $spawned += $child
    }
    Start-Sleep -Seconds 1
    $records = @()
    $kinds = @("godot","caddy")
    for ($i=0; $i -lt $spawned.Count; $i++) {
        $p = Get-Process -Id $spawned[$i].Id -ErrorAction Stop
        $records += [PSCustomObject]@{
            name = $kinds[$i]
            pid = $p.Id
            path = $p.Path
            started = $p.StartTime.ToUniversalTime().ToString("o")
        }
    }
    # Simulate the old launcher writing an array through the pipeline.
    @($records) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $state -Encoding UTF8
    & (Join-Path $PSScriptRoot "Stop-PVP-Public.ps1") -Quiet

    foreach ($p in $spawned) {
        try { $p.WaitForExit(3000) | Out-Null } catch {}
        if (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) {
            throw ("Tracked process was not stopped: " + $p.Id)
        }
    }
    if (Test-Path -LiteralPath $state) {
        throw "Successful stop did not clear its process registry."
    }

    # A stale or forged PID record must not kill a different process.
    $live = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile","-NonInteractive","-Command","Start-Sleep -Seconds 120") -WindowStyle Hidden -PassThru
    $spawned += $live
    Start-Sleep -Milliseconds 600
    $live = Get-Process -Id $live.Id -ErrorAction Stop
    $wrong = [PSCustomObject]@{
        name = "cloudflared"
        pid = $live.Id
        path = "C:\not-real\cloudflared.exe"
        started = $live.StartTime.ToUniversalTime().ToString("o")
    }
    ConvertTo-Json -InputObject ([object[]]@($wrong)) -Depth 4 | Set-Content -LiteralPath $state -Encoding UTF8
    & (Join-Path $PSScriptRoot "Stop-PVP-Public.ps1") -Quiet
    if (-not (Get-Process -Id $live.Id -ErrorAction SilentlyContinue)) {
        throw "Unrelated process was killed by a forged process record."
    }
    Write-Host "PVP_STOP_TEST_RESULT PASS"
} finally {
    foreach ($p in $spawned) {
        $still = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
        if ($still) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    }
    Remove-Item -LiteralPath $state -Force -ErrorAction SilentlyContinue
}
