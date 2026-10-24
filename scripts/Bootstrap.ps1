. "$PSScriptRoot/Common.ps1"
New-Item -ItemType Directory -Force -Path (Join-Path $script:ProjectRoot '.secrets') | Out-Null
Protect-BartaSecrets
$path = Get-LinuxProjectPath
& wsl.exe -d $script:Distro -u root --exec python3 "$path/scripts/bootstrap.py"
if ($LASTEXITCODE -ne 0) { throw 'Administrator setup failed.' }
