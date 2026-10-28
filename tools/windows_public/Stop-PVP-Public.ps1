param([switch]$Quiet)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$state = Join-Path $root ".pvp-local\processes.json"
if (-not (Test-Path -LiteralPath $state)) {
    if (-not $Quiet) { Write-Host "[PVP] No active session is recorded." }
    return
}
try {
    $entries = @(Get-Content -LiteralPath $state -Raw -Encoding UTF8 | ConvertFrom-Json)
} catch {
    Write-Host "[PVP] Cannot read process registry; refusing to kill unrelated processes." -ForegroundColor Red
    return
}
[Array]::Reverse($entries)
foreach ($entry in $entries) {
    if (-not $entry.pid -or -not $entry.path) { continue }
    $process = Get-Process -Id ([int]$entry.pid) -ErrorAction SilentlyContinue
    if (-not $process) { continue }
    try {
        $actualPath = $process.Path
        $expectedPath = [IO.Path]::GetFullPath([string]$entry.path)
        if (-not $actualPath -or -not $actualPath.Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)) {
            Write-Host ("[PVP] Skipped PID " + $entry.pid + " (executable changed).")
            continue
        }
        if ($entry.started) {
            $expectedStart = [DateTime]::Parse([string]$entry.started).ToUniversalTime()
            $actualStart = $process.StartTime.ToUniversalTime()
            if ([Math]::Abs(($actualStart - $expectedStart).TotalSeconds) -gt 5) {
                Write-Host ("[PVP] Skipped PID " + $entry.pid + " (process start time changed).")
                continue
            }
        }
        Stop-Process -Id $process.Id -Force -ErrorAction Stop
        if (-not $Quiet) { Write-Host ("[PVP] Stopped " + $entry.name) }
    } catch {
        Write-Host ("[PVP] Unable to stop PID " + $entry.pid + ": " + $_.Exception.Message)
    }
}
Remove-Item -LiteralPath $state -Force -ErrorAction SilentlyContinue
if (-not $Quiet) { Write-Host "[PVP] Stop complete. Saves and backups were preserved." }
