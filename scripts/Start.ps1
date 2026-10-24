[CmdletBinding()]
param([switch]$DownloadImages)
. "$PSScriptRoot/Common.ps1"
$envValues = Get-BartaEnvironment
Start-BartaRuntimeKeeper
& wsl.exe -d $script:Distro -u root --exec systemctl start docker
if ($LASTEXITCODE -ne 0) { throw 'Docker could not start. Run Install-Windows.ps1 first.' }
if ($DownloadImages) {
    Invoke-BartaCompose -Arguments @('pull', '--policy', 'always')
}
Invoke-BartaCompose -Arguments @('up', '-d', '--pull', 'never', '--wait', '--wait-timeout', '180')
Write-Host "Server started. Configured address: $($envValues.SITE_URL)"
Write-Host 'If the WSL address changed, run Enable-Lan.ps1 as Administrator again.'
