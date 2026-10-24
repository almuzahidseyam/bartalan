[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9._-]{2,21}$')][string]$Username)
. "$PSScriptRoot/Common.ps1"
$securePassword = Read-Host "Password for $Username (at least 10 characters)" -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
try {
    $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if ($password.Length -lt 10) { throw 'Use at least 10 characters.' }
    Invoke-BartaCompose -Arguments @('exec','-T','mattermost','/mattermost/bin/mmctl','--local','user','create',
        '--email',"$Username@bartalan.invalid",'--username',$Username,'--password',$password)
    Invoke-BartaCompose -Arguments @('exec','-T','mattermost','/mattermost/bin/mmctl','--local','team','users','add','bartalan',$Username)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    $password = $null
}
Write-Host "Created $Username and added the account to BartaLAN."
