# Check that an allocated trycloudflare.com URL really serves PVP's HTML
# before claiming the session is public. A URL in cloudflared's log alone
# does not prove DNS registration or browser reachability.
function Test-PvpPublicHttp {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [scriptblock]$Probe
    )
    if ($Url -notmatch '^https://[a-z0-9-]+\.trycloudflare\.com/?$') {
        return $false
    }
    if ($null -ne $Probe) {
        try { return [bool](& $Probe $Url) }
        catch { return $false }
    }
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 8 -MaximumRedirection 0 -ErrorAction Stop
        return ([int]$response.StatusCode -eq 200) -and
            ([string]$response.Content -match '(?i)<!doctype html|<html')
    } catch {
        return $false
    }
}

function Wait-PvpPublicHttp {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [int]$Attempts = 10,
        [int]$PauseMilliseconds = 2500,
        [scriptblock]$Probe
    )
    if ($Attempts -lt 1 -or $Attempts -gt 100) { throw "Invalid HTTP probe attempt count." }
    for ($i = 0; $i -lt $Attempts; $i++) {
        if (Test-PvpPublicHttp -Url $Url -Probe $Probe) { return $true }
        if ($i -lt ($Attempts - 1) -and $PauseMilliseconds -gt 0) {
            Start-Sleep -Milliseconds $PauseMilliseconds
        }
    }
    return $false
}

function Show-PvpPublicDnsStatus {
    param([Parameter(Mandatory=$true)][string]$Url)
    if ($Url -notmatch '^https://([a-z0-9-]+\.trycloudflare\.com)/?$') {
        Write-Host "[PVP] Invalid Quick Tunnel URL format."
        return
    }
    $dnsName = $Matches[1]
    foreach ($dnsServer in @("default", "1.1.1.1", "8.8.8.8")) {
        try {
            if ($dnsServer -eq "default") {
                $answers = @(Resolve-DnsName -Name $dnsName -Type A -DnsOnly -QuickTimeout -ErrorAction Stop)
            } else {
                $answers = @(Resolve-DnsName -Name $dnsName -Server $dnsServer -Type A -DnsOnly -QuickTimeout -ErrorAction Stop)
            }
            $ips = @($answers | Where-Object { $_.Type -eq "A" -and $_.IPAddress } | Select-Object -ExpandProperty IPAddress -Unique)
            if ($ips.Count -gt 0) {
                Write-Host ("[PVP] DNS " + $dnsServer + ": " + ($ips -join ", "))
            } else {
                Write-Host ("[PVP] DNS " + $dnsServer + ": no A record returned")
            }
        } catch {
            Write-Host ("[PVP] DNS " + $dnsServer + ": unresolved or query blocked")
        }
    }
    Write-Host "[PVP] If public resolvers work but your browser shows NXDOMAIN, use 'ipconfig /flushdns' in a separate PowerShell and reload Chrome."
    Write-Host "[PVP] If public resolvers do not return an address, the Quick Tunnel hostname is not yet DNS-accessible. Restarting the tunnel may obtain a different hostname."
}
