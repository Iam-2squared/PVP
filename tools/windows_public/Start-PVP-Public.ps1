param()
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$runtime = Join-Path $root ".pvp-local"
$bin = Join-Path $runtime "bin"
$logs = Join-Path $runtime "logs"
$web = Join-Path $runtime "web"
$state = Join-Path $runtime "processes.json"
$script:children = @()
$script:active = $false
foreach ($dir in @($runtime, $bin, $logs)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

function Say([string]$message) { Write-Host ("[PVP] " + $message) -ForegroundColor Cyan }

function Download-Official([string]$uri, [string]$destination, [string]$digest = "") {
    Say ("Downloading from official release: " + $uri)
    $temp = $destination + ".downloading"
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    try {
        Invoke-WebRequest -Uri $uri -OutFile $temp -UseBasicParsing -TimeoutSec 900
        if ((Get-Item -LiteralPath $temp).Length -lt 100000) { throw "Downloaded file is unexpectedly small." }
        if ($digest -match "^sha256:([a-fA-F0-9]{64})$") {
            $actual = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash
            if ($actual -ne $Matches[1]) { throw "Official release SHA256 verification failed." }
        }
        Move-Item -LiteralPath $temp -Destination $destination -Force
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    }
}

function Ensure-Caddy {
    $exe = Join-Path $bin "caddy.exe"
    if (Test-Path -LiteralPath $exe) { return $exe }
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/caddyserver/caddy/releases/latest" -Headers @{"User-Agent"="PVP-Windows-Host"}
    $asset = @($release.assets | Where-Object { $_.name -match "^caddy_.*_windows_amd64\.zip$" }) | Select-Object -First 1
    if (-not $asset) { throw "Official Caddy Windows amd64 release was not found." }
    $archive = Join-Path $bin "caddy-release.zip"
    Download-Official $asset.browser_download_url $archive $asset.digest
    $extract = Join-Path $bin "caddy-extracted"
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    Expand-Archive -Path $archive -DestinationPath $extract -Force
    $found = Get-ChildItem $extract -Filter "caddy.exe" -Recurse -File | Select-Object -First 1
    if (-not $found) { throw "Caddy executable was not in the archive." }
    Copy-Item -LiteralPath $found.FullName -Destination $exe -Force
    Remove-Item $archive -Force
    Remove-Item $extract -Recurse -Force
    return $exe
}

function Ensure-Cloudflared {
    $exe = Join-Path $bin "cloudflared.exe"
    if (Test-Path -LiteralPath $exe) { return $exe }
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/cloudflare/cloudflared/releases/latest" -Headers @{"User-Agent"="PVP-Windows-Host"}
    $asset = @($release.assets | Where-Object { $_.name -eq "cloudflared-windows-amd64.exe" }) | Select-Object -First 1
    if (-not $asset) { throw "Official cloudflared Windows amd64 release was not found." }
    Download-Official $asset.browser_download_url $exe $asset.digest
    return $exe
}

function Find-Godot {
    $choices = @()
    if ($env:GODOT_EXE) { $choices += $env:GODOT_EXE }
    foreach ($name in @("godot", "godot4")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { $choices += $cmd.Source }
    }
    $choices += (Join-Path $bin "Godot_v4.6.3-stable_win64_console.exe")
    $choices += (Join-Path $bin "Godot_v4.6.3-stable_win64.exe")
    foreach ($dir in @($root, (Join-Path $env:USERPROFILE "Downloads"), (Join-Path $env:USERPROFILE "Desktop"))) {
        if (Test-Path $dir) {
            $choices += @(Get-ChildItem -Path $dir -Filter "Godot*win64*.exe" -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        }
    }
    foreach ($candidate in $choices) {
        if (-not $candidate -or -not (Test-Path -LiteralPath $candidate)) { continue }
        $path = (Resolve-Path -LiteralPath $candidate).Path
        if ($path -match '(?i)_win64\.exe$') {
            # Windows CLI tasks must use the console executable shipped with
            # the official Godot Windows editor, not the GUI-subsystem stub.
            $consolePath = $path.Substring(0, $path.Length - 4) + "_console.exe"
            if (Test-Path -LiteralPath $consolePath) { $path = $consolePath }
        }
        try {
            $version = (& $path --version 2>&1 | Select-Object -First 1 | Out-String).Trim()
            if ($version -match "^4\.6\.3") { return $path }
        } catch {}
    }
    Say "Godot 4.6.3 not found. Downloading the official Windows editor."
    $archive = Join-Path $bin "godot-4.6.3.zip"
    $uri = "https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_win64.exe.zip"
    Download-Official $uri $archive
    Expand-Archive -Path $archive -DestinationPath $bin -Force
    $exe = Join-Path $bin "Godot_v4.6.3-stable_win64_console.exe"
    if (-not (Test-Path $exe)) { throw "Godot console editor was not extracted successfully." }
    Remove-Item $archive -Force
    return $exe
}

function Ensure-WebTemplates {
    $target = Join-Path $env:APPDATA "Godot\export_templates\4.6.3.stable"
    $archive = Join-Path $bin "godot-export-templates.zip"
    & (Join-Path $PSScriptRoot "Install-WebTemplates.ps1") -TemplateDir $target -ArchiveCache $archive
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
        throw "Web export template installer exited with an error."
    }
}

function Test-PortFree([int]$port) {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
    try { $listener.Start() } catch { throw "Local TCP port $port is in use. Run Stop-PVP-Public.bat and retry." }
    finally { $listener.Stop() }
}

function Start-Managed([string]$name, [string]$exe, [string]$arguments) {
    $out = Join-Path $logs ($name + ".out.log")
    $err = Join-Path $logs ($name + ".err.log")
    $process = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $started = ""
    try { $started = $process.StartTime.ToUniversalTime().ToString("o") } catch {}
    $script:children += [PSCustomObject]@{ name=$name; pid=$process.Id; path=$exe; started=$started }
    @($script:children) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $state -Encoding UTF8
    Say ("Started $name (PID " + $process.Id + ")")
    return $process
}

function Wait-TcpPort([int]$port, [System.Diagnostics.Process]$process) {
    for ($i=0; $i -lt 50; $i++) {
        if ($process.HasExited) { throw "A process exited unexpectedly. See .pvp-local/logs." }
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $result = $client.BeginConnect("127.0.0.1", $port, $null, $null)
            if ($result.AsyncWaitHandle.WaitOne(250) -and $client.Connected) { return }
        } catch {} finally { $client.Close() }
        Start-Sleep -Milliseconds 400
    }
    throw "Timed out waiting for local port $port. See .pvp-local/logs."
}

function Write-Gzip([string]$path) {
    $destination = $path + ".gz"
    $inputStream = [IO.File]::OpenRead($path)
    try {
        $outputStream = [IO.File]::Create($destination)
        try {
            $compressor = [System.IO.Compression.GZipStream]::new($outputStream, [System.IO.Compression.CompressionLevel]::Optimal)
            try { $inputStream.CopyTo($compressor) } finally { $compressor.Dispose() }
        } finally { $outputStream.Dispose() }
    } finally { $inputStream.Dispose() }
}

function Backup-Profiles {
    $projectFile = Join-Path $root "project.godot"
    $nameLine = Get-Content -LiteralPath $projectFile -Encoding UTF8 | Where-Object { $_.StartsWith("config/name=") } | Select-Object -First 1
    if (-not $nameLine) { throw "Game project name was not found in project.godot." }
    $projectName = $nameLine.Substring("config/name=".Length).Trim('"')
    $source = Join-Path (Join-Path (Join-Path $env:APPDATA "Godot\app_userdata") $projectName) "battle_server\profiles.json"
    if (-not (Test-Path -LiteralPath $source)) { return }
    $backupDir = Join-Path $runtime "backups"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    $dest = Join-Path $backupDir ("profiles-" + $timestamp + ".json")
    Copy-Item -LiteralPath $source -Destination $dest
    try { $null = Get-Content -LiteralPath $dest -Raw -Encoding UTF8 | ConvertFrom-Json } catch {
        Remove-Item -LiteralPath $dest -Force
        throw "Saved profile JSON was corrupt. Refusing to start; existing save was not overwritten."
    }
    Say "Existing profile save was backed up locally before startup."
}

function Build-Web([string]$godot) {
    $stage = Join-Path $runtime "web-next"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Say "Importing project resources using the console Godot executable..."
    $importLog = Join-Path $logs "godot-import.log"
    & $godot --headless --path $root --import --log-file $importLog
    if ($LASTEXITCODE -ne 0) {
        $importExit = $LASTEXITCODE
        Say "Import failed; the last log lines are:"
        if (Test-Path -LiteralPath $importLog) {
            Get-Content -LiteralPath $importLog -Tail 30 | ForEach-Object { Write-Host $_ }
        }
        throw ("Godot import failed (exit " + $importExit + "). See .pvp-local/logs/godot-import.log")
    }
    Say "Exporting current Web game..."
    & $godot --headless --path $root --export-release Web (Join-Path $stage "index.html")
    if ($LASTEXITCODE -ne 0) { throw "Godot Web export failed. Confirm version 4.6.3 and templates." }
    foreach ($required in @("index.html","index.js","index.wasm","index.pck")) {
        if (-not (Test-Path (Join-Path $stage $required))) { throw "Web export missing $required." }
    }
    foreach ($file in Get-ChildItem -Path $stage -File | Where-Object { $_.Extension -in @(".pck",".wasm",".js") }) {
        Say ("Compressing " + $file.Name)
        Write-Gzip $file.FullName
    }
    $old = Join-Path $runtime "web-previous"
    if (Test-Path $old) { Remove-Item $old -Recurse -Force }
    if (Test-Path $web) { Move-Item -LiteralPath $web -Destination $old }
    Move-Item -LiteralPath $stage -Destination $web
    if (Test-Path $old) { Remove-Item $old -Recurse -Force }
}

function Make-Caddyfile {
    $webPath = $web.Replace("\", "/")
    if ($webPath.Contains('"')) { throw "Quote character in project path is unsupported." }
    $caddyfile = Join-Path $runtime "Caddyfile"
    $text = @"
{
    admin off
    auto_https off
}
http://127.0.0.1:18080 {
    handle /ws {
        reverse_proxy 127.0.0.1:8910
    }
    handle {
        root * "$webPath"
        header {
            Cross-Origin-Opener-Policy same-origin
            Cross-Origin-Embedder-Policy require-corp
            X-Content-Type-Options nosniff
        }
        encode gzip
        file_server {
            precompressed gzip
        }
    }
}
"@
    Set-Content -LiteralPath $caddyfile -Value $text -Encoding Ascii
    return $caddyfile
}

function Stop-Children {
    if (Test-Path $state) {
        & (Join-Path $PSScriptRoot "Stop-PVP-Public.ps1") -Quiet
    }
}

try {
    if (Test-Path $state) {
        throw "Previous session is recorded. Run Stop-PVP-Public.bat before starting another."
    }
    Test-PortFree 8910
    Test-PortFree 18080
    Say "Preparing a free PC-hosted PVP session. No router settings or card required."
    $godot = Find-Godot
    Ensure-WebTemplates
    $caddy = Ensure-Caddy
    $cloudflared = Ensure-Cloudflared
    Backup-Profiles
    Build-Web $godot
    $caddyfile = Make-Caddyfile
    Say "Checking Caddy configuration..."
    & $caddy validate --config $caddyfile --adapter caddyfile
    if ($LASTEXITCODE -ne 0) { throw "Caddyfile validation failed." }
    $game = Start-Managed "godot" $godot ('--headless --path "' + $root + '" --script res://tools/run_battle_server.gd -- --bind=127.0.0.1 --port=8910')
    Wait-TcpPort 8910 $game
    $proxy = Start-Managed "caddy" $caddy ('run --config "' + $caddyfile + '" --adapter caddyfile')
    Wait-TcpPort 18080 $proxy
    $localResponse = Invoke-WebRequest -Uri "http://127.0.0.1:18080/" -UseBasicParsing -TimeoutSec 10
    if ($localResponse.StatusCode -ne 200) { throw "Local web server returned an unexpected status." }
    $tunnel = Start-Managed "cloudflared" $cloudflared '--no-autoupdate tunnel --url http://127.0.0.1:18080'
    $publicUrl = ""
    Say "Requesting a temporary HTTPS URL from Cloudflare..."
    for ($i=0; $i -lt 100; $i++) {
        if ($tunnel.HasExited) { throw "Cloudflare Tunnel exited. Check .pvp-local/logs/cloudflared.err.log." }
        $content = ""
        foreach ($file in @((Join-Path $logs "cloudflared.err.log"), (Join-Path $logs "cloudflared.out.log"))) {
            if (Test-Path $file) {
                try { $content += [IO.File]::ReadAllText($file) } catch {}
            }
        }
        $matchesUrl = [regex]::Matches($content,'https://[a-z0-9-]+\.trycloudflare\.com','IgnoreCase')
        if ($matchesUrl.Count -gt 0) { $publicUrl = $matchesUrl[0].Value; break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $publicUrl) { throw "Cloudflare did not provide a public URL. Check network access and logs." }
    $script:active = $true
    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host " PVP IS PUBLIC WHILE THIS PC AND SESSION ARE RUNNING" -ForegroundColor Green
    Write-Host ("  PLAY URL: " + $publicUrl) -ForegroundColor White
    Write-Host ("  GAME WSS: " + $publicUrl.Replace("https://","wss://") + "/ws") -ForegroundColor White
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host "Give friends the PLAY URL. Game server is selected automatically."
    Write-Host "The URL changes on each restart. SAVE YOUR RECOVERY CODE in Player Settings."
    Write-Host "Do not share recovery codes. URL visitors can join this test PvP game."
    Write-Host ""
    try { Set-Clipboard -Value $publicUrl -ErrorAction Stop; Say "Play URL copied to clipboard." } catch {}
    try { Start-Process $publicUrl | Out-Null } catch {}
    $null = Read-Host "Press Enter here to STOP public hosting"
} catch {
    Write-Host ("[PVP] ERROR: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host "If necessary check .pvp-local/logs and docs/WINDOWS_PUBLIC_HOST.md"
} finally {
    Stop-Children
    Say "Hosting stopped. Profile data and backups were not removed."
}
if (-not $script:active) { exit 1 }
