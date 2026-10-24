. "$PSScriptRoot/Common.ps1"
Invoke-BartaCompose -Arguments @('ps')
$values = Get-BartaEnvironment
try {
    $reply = Invoke-RestMethod -Uri "http://127.0.0.1:$($values.APP_PORT)/api/v4/system/ping" -TimeoutSec 10
    Write-Host "Local health: $($reply.status)"
} catch { Write-Warning 'Local health endpoint is not reachable.' }
Write-Host "Client address: $($values.SITE_URL)"
