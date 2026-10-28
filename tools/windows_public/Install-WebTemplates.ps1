param(
    [Parameter(Mandatory=$true)][string]$TemplateDir,
    [Parameter(Mandatory=$true)][string]$ArchiveCache,
    [switch]$NonInteractive
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# Godot 4.6.3 Web export with thread_support=false and extensions_support=false.
# The existing web_release.zip / web_debug.zip are NOT replacements for these.
$needed = @("web_nothreads_debug.zip", "web_nothreads_release.zip")
$officialUrl = "https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_export_templates.tpz"
$officialSHA256 = "3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8"

function Find-MissingTemplates {
    $missing = @()
    foreach ($name in $needed) {
        $dest = Join-Path $TemplateDir $name
        if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) {
            $missing += $name
            continue
        }
        if ((Get-Item -LiteralPath $dest).Length -lt 100000) {
            $missing += $name
        }
    }
    return $missing
}

New-Item -ItemType Directory -Path $TemplateDir -Force | Out-Null
$missing = @(Find-MissingTemplates)
if ($missing.Count -eq 0) {
    Write-Host "[PVP] Correct no-threads Web templates are already installed."
    return
}
Write-Host ("[PVP] Missing Godot Web templates: " + ($missing -join ", "))
if (-not $NonInteractive) {
    Write-Host "[PVP] Previous setup copied the threaded templates; this correction needs the official 4.6.3 package again."
    $answer = Read-Host "Download the official template package (about 1.26 GB) now? [Y/n]"
    if ($answer -match "^[Nn]") { throw "Web export templates are required. No existing saves or tools were removed." }
}

$archiveParent = Split-Path -Parent $ArchiveCache
New-Item -ItemType Directory -Path $archiveParent -Force | Out-Null
$validArchive = $false
if (Test-Path -LiteralPath $ArchiveCache -PathType Leaf) {
    $archiveSHA = (Get-FileHash -LiteralPath $ArchiveCache -Algorithm SHA256).Hash.ToLowerInvariant()
    $validArchive = $archiveSHA -eq $officialSHA256
}
if (-not $validArchive) {
    Write-Host "[PVP] Downloading official Godot 4.6.3 export templates..."
    $temporary = $ArchiveCache + ".downloading"
    try {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        Invoke-WebRequest -Uri $officialUrl -OutFile $temporary -UseBasicParsing -TimeoutSec 1200
        $actualSHA = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualSHA -ne $officialSHA256) { throw "Official export package SHA256 verification failed." }
        Move-Item -LiteralPath $temporary -Destination $ArchiveCache -Force
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zip = [System.IO.Compression.ZipFile]::OpenRead($ArchiveCache)
try {
    $entries = @{}
    foreach ($entry in $zip.Entries) {
        $fullName = $entry.FullName.Replace("\", "/")
        if ($fullName -match "^templates/(web_nothreads_(debug|release)\.zip)$") {
            $entries[$Matches[1]] = $entry
        }
    }
    foreach ($name in $missing) {
        if (-not $entries.ContainsKey($name)) {
            throw ("Official archive does not contain templates/" + $name)
        }
    }
    foreach ($name in $missing) {
        $entry = $entries[$name]
        $destination = Join-Path $TemplateDir $name
        $temporary = $destination + ".installing"
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        try {
            Write-Host ("[PVP] Extracting official " + $name)
            $sourceStream = $entry.Open()
            try {
                $destStream = [System.IO.File]::Create($temporary)
                try { $sourceStream.CopyTo($destStream) }
                finally { $destStream.Dispose() }
            } finally { $sourceStream.Dispose() }
            if ((Get-Item -LiteralPath $temporary).Length -ne $entry.Length -or $entry.Length -lt 100000) {
                throw ("Extracted template has the wrong size: " + $name)
            }
            # The nested Web template must itself be a readable ZIP file.
            $webArchive = [System.IO.Compression.ZipFile]::OpenRead($temporary)
            try {
                if ($webArchive.Entries.Count -lt 2) { throw ("Invalid Web template: " + $name) }
            } finally { $webArchive.Dispose() }
            Move-Item -LiteralPath $temporary -Destination $destination -Force
        } finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        }
    }
} finally { $zip.Dispose() }

$remaining = @(Find-MissingTemplates)
if ($remaining.Count -ne 0) { throw ("Incomplete template installation: " + ($remaining -join ", ")) }
Write-Host "[PVP] Godot Web no-threads templates installed successfully."
# Remove the large archive after both required templates have been verified,
# without deleting existing Godot versions or any saved player profiles.
Remove-Item -LiteralPath $ArchiveCache -Force
