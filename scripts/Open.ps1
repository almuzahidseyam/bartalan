. "$PSScriptRoot/Common.ps1"
$values = Get-BartaEnvironment
Start-Process -FilePath $values.SITE_URL
