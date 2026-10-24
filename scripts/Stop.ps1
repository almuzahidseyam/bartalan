. "$PSScriptRoot/Common.ps1"
Invoke-BartaCompose -Arguments @('stop')
Stop-BartaRuntimeKeeper
Write-Host 'Server stopped. Messages and files are retained.'
