$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Verify-PublicUrl.ps1")

$url = "https://whom-mechanics-shot-sides.trycloudflare.com"
$script:attempts = 0
$mock = {
    param([string]$probeUrl)
    if ($probeUrl -ne "https://whom-mechanics-shot-sides.trycloudflare.com") {
        throw "Unexpected URL in test."
    }
    $script:attempts += 1
    return ($script:attempts -ge 3)
}
if (-not (Wait-PvpPublicHttp -Url $url -Attempts 4 -PauseMilliseconds 0 -Probe $mock)) {
    throw "Healthy URL was not recognized after two initial failures."
}
if ($script:attempts -ne 3) {
    throw "Reachability verification did not finish at the first successful HTTP probe."
}

$script:attempts = 0
$dead = {
    param([string]$probeUrl)
    $script:attempts += 1
    return $false
}
if (Wait-PvpPublicHttp -Url $url -Attempts 3 -PauseMilliseconds 0 -Probe $dead) {
    throw "NXDOMAIN/unreachable URL was incorrectly called public."
}
if ($script:attempts -ne 3) {
    throw "Unreachable URL probe count mismatch."
}

$fakeOk = { param($probeUrl) return $true }
if (Test-PvpPublicHttp -Url "http://whom-mechanics-shot-sides.trycloudflare.com" -Probe $fakeOk) {
    throw "HTTP URL was accepted without TLS."
}
if (Test-PvpPublicHttp -Url "https://trycloudflare.com.attacker.example" -Probe $fakeOk) {
    throw "Non-Quick-Tunnel hostname was accepted."
}
if (Test-PvpPublicHttp -Url "https://whom-mechanics-shot-sides.trycloudflare.com.evil.test" -Probe $fakeOk) {
    throw "Hostname suffix was not validated."
}
Write-Host "PVP_PUBLIC_URL_TEST_RESULT PASS"
