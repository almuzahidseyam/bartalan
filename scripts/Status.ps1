. "$PSScriptRoot/Common.ps1"
Invoke-BartaCompose -Arguments @('ps')
$values = Get-BartaEnvironment
try {
    $reply = Invoke-RestMethod -Uri "https://127.0.0.1:$($values.APP_PORT)/api/v4/system/ping" -TimeoutSec 10
    Write-Host "Local health: $($reply.status)"
} catch { Write-Warning 'Trusted HTTPS health check failed. Check server status and run Trust-LocalCertificate.ps1 for this Windows account.' }
Write-Host "Client address: $($values.SITE_URL)"
