[CmdletBinding()]
param([Parameter(Mandatory)][string]$LanAddress)
. "$PSScriptRoot/Common.ps1"
$values = Get-BartaEnvironment
& netsh.exe interface portproxy delete v4tov4 "listenaddress=$LanAddress" "listenport=$($values.APP_PORT)"
if ($LASTEXITCODE -ne 0) { throw 'Could not remove port forwarding. Run as Administrator.' }
& netsh.exe interface portproxy delete v4tov4 'listenaddress=127.0.0.1' "listenport=$($values.APP_PORT)"
if ($LASTEXITCODE -ne 0) { throw 'Could not remove host-local port forwarding.' }
Get-NetFirewallRule -Name 'BartaLAN-Local-Chat' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
Write-Host 'BartaLAN LAN forwarding and its firewall rule removed.'
