[CmdletBinding()]
param([Parameter(Mandatory)][string]$LanAddress, [Parameter(Mandatory)][string]$Subnet)
. "$PSScriptRoot/Common.ps1"
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open PowerShell as Administrator to add this LAN-only port forwarding and firewall rule.'
}
$parsedAddress = $null
if (![Net.IPAddress]::TryParse($LanAddress, [ref]$parsedAddress) -or $parsedAddress.AddressFamily -ne 'InterNetwork') { throw 'An IPv4 LAN address is required.' }
if ($Subnet -notmatch '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)[0-9.]+/\d{1,2}$') { throw 'Specify your private IPv4 subnet in CIDR notation.' }
$networkText, $prefixText = $Subnet.Split('/')
$networkIp = $null
if (![Net.IPAddress]::TryParse($networkText, [ref]$networkIp) -or $networkIp.AddressFamily -ne 'InterNetwork') { throw 'Invalid subnet address.' }
$prefixLength = [int]$prefixText
$minimumPrefix = if ($networkText.StartsWith('10.')) {8} elseif ($networkText.StartsWith('192.168.')) {16} else {12}
if ($prefixLength -lt $minimumPrefix -or $prefixLength -gt 32) { throw 'The allowed subnet must remain entirely inside a private IPv4 range.' }
function ConvertTo-IPv4Number([Net.IPAddress]$Address) {
    $octets = $Address.GetAddressBytes()
    return [uint64]$octets[0] * 16777216 + [uint64]$octets[1] * 65536 + [uint64]$octets[2] * 256 + [uint64]$octets[3]
}
$mask = ([uint64]4294967295 -shl (32 - $prefixLength)) -band [uint64]4294967295
$networkNumber = ConvertTo-IPv4Number $networkIp
if (($networkNumber -band $mask) -ne $networkNumber) { throw 'Use the canonical network address, for example 192.168.1.0/24.' }
if (((ConvertTo-IPv4Number $parsedAddress) -band $mask) -ne $networkNumber) { throw 'The selected LAN address must belong to the allowed subnet.' }
$localAddress = Get-NetIPAddress -AddressFamily IPv4 -IPAddress $LanAddress -ErrorAction Stop
$values = Get-BartaEnvironment
if ($values.BIND_ADDRESS -ne '0.0.0.0') { throw 'Set BIND_ADDRESS=0.0.0.0 in .env and restart first.' }
if (([Uri]$values.SITE_URL).Host -ne $LanAddress) { throw 'SITE_URL must use the selected LAN address. Update .env and restart first.' }
$linuxAddress = (& wsl.exe -d $script:Distro -u root --exec hostname -I | Out-String).Trim().Split(' ')[0]
$parsedLinuxAddress = $null
if (![Net.IPAddress]::TryParse($linuxAddress, [ref]$parsedLinuxAddress)) { throw 'Could not determine the WSL address.' }
$port = [int]$values.APP_PORT
if ($port -lt 1024 -or $port -gt 65535) { throw 'APP_PORT must be between 1024 and 65535.' }
foreach ($rangeLine in (& netsh.exe interface ipv4 show excludedportrange protocol=tcp)) {
    if ($rangeLine -match '^\s*(\d+)\s+(\d+)\s*\*?\s*$' -and $port -ge [int]$matches[1] -and $port -le [int]$matches[2]) {
        throw "Windows has reserved TCP port $port. Choose a free APP_PORT, update SITE_URL, and restart before enabling LAN access."
    }
}
Start-Service -Name iphlpsvc -ErrorAction Stop
& netsh.exe interface portproxy add v4tov4 "listenaddress=$LanAddress" "listenport=$port" "connectaddress=$linuxAddress" "connectport=$port"
if ($LASTEXITCODE -ne 0) { throw 'Could not add port forwarding.' }
& netsh.exe interface portproxy add v4tov4 'listenaddress=127.0.0.1' "listenport=$port" "connectaddress=$linuxAddress" "connectport=$port"
if ($LASTEXITCODE -ne 0) { throw 'Could not add host-local port forwarding.' }
$rule = 'BartaLAN-Local-Chat'
Get-NetFirewallRule -Name $rule -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -Name $rule -DisplayName 'BartaLAN - local chat only' -Direction Inbound -Action Allow -Protocol TCP -LocalAddress $LanAddress -LocalPort $port -RemoteAddress $Subnet -Profile Any | Out-Null
$reachable = $false
for ($attempt = 0; $attempt -lt 10; $attempt++) {
    try {
        $reply = Invoke-RestMethod -Uri "http://${LanAddress}:$port/api/v4/system/ping" -TimeoutSec 2
        if ($reply.status -eq 'OK') { $reachable = $true; break }
    } catch {}
    Start-Sleep -Milliseconds 500
}
if (!$reachable) { throw 'Rules were saved, but the LAN health endpoint is unreachable. Check Windows IP Helper, reserved ports, and forwarding before using this address.' }
$privateDir = Join-Path $script:ProjectRoot '.secrets'
New-Item -ItemType Directory -Force -Path $privateDir | Out-Null
@{lan_address=$LanAddress; subnet=$Subnet; wsl_address=$linuxAddress; port=$port; updated_at=(Get-Date).ToUniversalTime().ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $privateDir 'lan-access.json') -Encoding UTF8
Write-Host "LAN access enabled: http://${LanAddress}:$port (allowed clients: $Subnet)."
Write-Host 'No router port forwarding or internet tunnel was configured.'
