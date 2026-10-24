. "$PSScriptRoot/Common.ps1"
$path = Get-LinuxProjectPath
$values = Get-BartaEnvironment
$destination = Join-Path $script:ProjectRoot 'offline-bundle'
New-Item -ItemType Directory -Force -Path $destination | Out-Null
& wsl.exe -d $script:Distro -u root --exec docker image save --output "$path/offline-bundle/images.tar" $values.MATTERMOST_IMAGE $values.POSTGRES_IMAGE $values.GATEWAY_IMAGE
if ($LASTEXITCODE -ne 0) { throw 'Image export failed.' }
$hash = (Get-FileHash -LiteralPath (Join-Path $destination 'images.tar') -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $destination 'SHA256SUMS'), "$hash  images.tar`n")
Write-Host 'Cached images exported to offline-bundle. This is not a chat-data backup or a full Windows/WSL installer.'
