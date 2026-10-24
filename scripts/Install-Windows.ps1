[CmdletBinding()]
param([string]$RuntimeDirectory = 'D:\BartaLAN\runtime')
. "$PSScriptRoot/Common.ps1"
$distros = (& wsl.exe --list --quiet | Out-String) -replace "`0", ''
if ($distros -split '\r?\n' | Where-Object {$_.Trim() -eq $script:Distro}) {
    Write-Host 'Reusing the existing BartaLAN runtime.'
} else {
    if (Test-Path -LiteralPath $RuntimeDirectory) { throw 'Runtime directory already exists. Choose a new empty location.' }
    $downloadDir = Join-Path $script:ProjectRoot '.runtime'
    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
    $archive = Join-Path $downloadDir 'ubuntu-base-24.04.3-base-amd64.tar.gz'
    $expected = '6bc2cde3930ad088b3bb46fa45279e96d25bc3810f209850ecbe4722711874f9'
    if (!(Test-Path -LiteralPath $archive)) {
        Write-Host 'Downloading the official Ubuntu base image (initial setup needs internet).'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-amd64.tar.gz' -OutFile $archive
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant() -ne $expected) {
        throw 'Ubuntu image checksum mismatch. Do not import this download.'
    }
    New-Item -ItemType Directory -Force -Path $RuntimeDirectory | Out-Null
    & wsl.exe --import $script:Distro $RuntimeDirectory $archive --version 2
    if ($LASTEXITCODE -ne 0) { throw 'WSL import failed.' }
}
$path = Get-LinuxProjectPath
& wsl.exe -d $script:Distro -u root --exec bash "$path/scripts/install-engine.sh"
if ($LASTEXITCODE -ne 0) { throw 'Docker installation failed.' }
& wsl.exe --terminate $script:Distro
& wsl.exe -d $script:Distro -u root --exec systemctl start docker
if ($LASTEXITCODE -ne 0) { throw 'Docker could not start.' }
& wsl.exe -d $script:Distro -u root --exec docker compose version
Write-Host "BartaLAN runtime is ready at $RuntimeDirectory. Other WSL distributions were preserved."
