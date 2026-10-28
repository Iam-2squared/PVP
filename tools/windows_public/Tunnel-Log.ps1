# Read a cloudflared-owned logfile while the process is still writing.
# Start-Process -RedirectStandardError may lock its redirected stream on
# Windows PowerShell 5.1, so do not depend on File.ReadAllText of that stream.
function Read-PvpLiveLog([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return "" }
    $stream = $null
    $reader = $null
    try {
        $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
        $stream = [System.IO.FileStream]::new(
            $path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            $share
        )
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true)
        return $reader.ReadToEnd()
    } catch [System.IO.IOException] {
        # The file may not have appeared yet, or may briefly be locked.
        return ""
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-PvpTunnelUrl([string[]]$paths) {
    $pattern = 'https://[a-z0-9-]+\.trycloudflare\.com\b'
    foreach ($path in $paths) {
        $content = Read-PvpLiveLog $path
        if ([string]::IsNullOrWhiteSpace($content)) { continue }
        $found = [regex]::Matches(
            $content, $pattern,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if ($found.Count -gt 0) { return $found[$found.Count - 1].Value }
    }
    return ""
}
