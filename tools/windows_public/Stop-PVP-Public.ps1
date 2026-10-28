param([switch]$Quiet)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$state = Join-Path $root ".pvp-local\processes.json"

if (-not (Test-Path -LiteralPath $state -PathType Leaf)) {
    if (-not $Quiet) { Write-Host "[PVP] No active session is recorded." }
    return
}

# Windows PowerShell 5.1 sometimes wraps a JSON array as a single object[].
# Flatten legacy and current registry shapes before reading one PID at a time.
$records = [System.Collections.ArrayList]::new()
function Add-Record([object]$value, [System.Collections.ArrayList]$destination) {
    if ($null -eq $value) { return }
    if ($value -is [System.Array]) {
        foreach ($element in $value) { Add-Record $element $destination }
        return
    }
    [void]$destination.Add($value)
}

try {
    $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $state -Raw -Encoding UTF8)
    Add-Record $parsed $records
} catch {
    Write-Host "[PVP] Cannot parse process registry. No processes were killed." -ForegroundColor Red
    Write-Host ("[PVP] Registry: " + $state)
    return
}

$allowedNames = @("cloudflared", "caddy", "godot")
$unresolved = [System.Collections.ArrayList]::new()
for ($i = $records.Count - 1; $i -ge 0; $i--) {
    $entry = $records[$i]
    if ($entry -isnot [PSCustomObject]) {
        Write-Host "[PVP] Skipped malformed registry entry."
        continue
    }
    $kind = [string]$entry.name
    $id = 0
    $pidValue = $entry.pid
    if (($allowedNames -notcontains $kind) -or $pidValue -is [System.Array] -or
        -not [int]::TryParse([string]$pidValue, [ref]$id) -or $id -le 0 -or
        $entry.path -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.path)) {
        Write-Host "[PVP] Skipped invalid or unrecognized process record."
        continue
    }

    $process = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($null -eq $process) { continue }
    try {
        $expectedPath = [IO.Path]::GetFullPath([string]$entry.path)
        $actualPath = $process.Path
        if (-not $actualPath -or -not $actualPath.Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)) {
            # A stale or reused PID must never cause an unrelated process to stop.
            Write-Host ("[PVP] Skipped PID " + $id + " (executable path mismatch).")
            continue
        }
        $started = [string]$entry.started
        if ([string]::IsNullOrWhiteSpace($started)) {
            Write-Host ("[PVP] Skipped PID " + $id + " (no trusted start time).")
            [void]$unresolved.Add($entry)
            continue
        }
        $expectedStart = [DateTime]::Parse($started).ToUniversalTime()
        $actualStart = $process.StartTime.ToUniversalTime()
        if ([Math]::Abs(($actualStart - $expectedStart).TotalSeconds) -gt 5) {
            Write-Host ("[PVP] Skipped PID " + $id + " (start time mismatch).")
            continue
        }
        Stop-Process -Id $id -Force -ErrorAction Stop
        if (-not $Quiet) { Write-Host ("[PVP] Stopped " + $kind + " (PID " + $id + ")") }
    } catch {
        Write-Host ("[PVP] Could not safely stop " + $kind + " PID " + $id + ": " + $_.Exception.Message)
        [void]$unresolved.Add($entry)
    }
}

if ($unresolved.Count -eq 0) {
    Remove-Item -LiteralPath $state -Force -ErrorAction SilentlyContinue
    if (-not $Quiet) { Write-Host "[PVP] Stop complete. Saves and backups were preserved." }
} else {
    $remaining = [object[]]$unresolved.ToArray()
    ConvertTo-Json -InputObject $remaining -Depth 4 | Set-Content -LiteralPath $state -Encoding UTF8
    Write-Host "[PVP] Some processes could not be verified/stopped. Registry was retained for safety." -ForegroundColor Yellow
}
