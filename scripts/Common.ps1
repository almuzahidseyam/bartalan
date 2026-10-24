$ErrorActionPreference = 'Stop'
$script:ProjectRoot = Split-Path $PSScriptRoot -Parent
$script:Distro = 'BartaLAN'

function Get-LinuxProjectPath {
    $windowsPath = $script:ProjectRoot.Replace('\', '/')
    $result = & wsl.exe -d $script:Distro -u root --exec wslpath -a $windowsPath
    if ($LASTEXITCODE -ne 0) { throw 'BartaLAN runtime is not installed. Run Install-Windows.ps1.' }
    return ($result | Out-String).Trim()
}

function Invoke-BartaCompose {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $path = Get-LinuxProjectPath
    & wsl.exe -d $script:Distro -u root --exec docker compose --project-directory $path @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Server command failed (exit $LASTEXITCODE)." }
}

function Get-BartaEnvironment {
    $envPath = Join-Path $script:ProjectRoot '.env'
    if (!(Test-Path -LiteralPath $envPath)) { throw 'Run Initialize.ps1 first.' }
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $envPath) {
        if ($line -match '^([A-Z_]+)=(.*)$') { $values[$matches[1]] = $matches[2] }
    }
    return $values
}

function Protect-BartaSecrets {
    if ($env:OS -ne 'Windows_NT') { return }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    foreach ($name in @('.env', '.secrets', 'backups')) {
        $secretPath = Join-Path $script:ProjectRoot $name
        if (!(Test-Path -LiteralPath $secretPath)) { continue }
        $inherit = if ((Get-Item -LiteralPath $secretPath).PSIsContainer) {'(OI)(CI)'} else {''}
        & icacls.exe $secretPath /inheritance:r /grant:r "*${sid}:${inherit}(F)" "*S-1-5-18:${inherit}(F)" "*S-1-5-32-544:${inherit}(F)" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not protect $name permissions." }
    }
}

function Start-BartaRuntimeKeeper {
    $runtimePath = Join-Path $script:ProjectRoot '.runtime'
    New-Item -ItemType Directory -Force -Path $runtimePath | Out-Null
    $keeperPath = Join-Path $runtimePath 'keeper.json'
    if (Test-Path -LiteralPath $keeperPath) {
        $saved = Get-Content -Raw -LiteralPath $keeperPath | ConvertFrom-Json
        $existing = Get-Process -Id $saved.process_id -ErrorAction SilentlyContinue
        if ($existing -and $existing.ProcessName -eq 'wsl' -and $existing.StartTime.ToUniversalTime().Ticks.ToString() -eq $saved.start_ticks) { return }
    }
    # systemd services alone do not keep a WSL distribution alive.
    $keeper = Start-Process -FilePath wsl.exe -ArgumentList @('-d',$script:Distro,'-u','root','--exec','sleep','infinity') -WindowStyle Hidden -PassThru
    @{process_id=$keeper.Id;start_ticks=$keeper.StartTime.ToUniversalTime().Ticks.ToString()} | ConvertTo-Json | Set-Content -LiteralPath $keeperPath -Encoding UTF8
}

function Stop-BartaRuntimeKeeper {
    $keeperPath = Join-Path $script:ProjectRoot '.runtime/keeper.json'
    if (!(Test-Path -LiteralPath $keeperPath)) { return }
    $saved = Get-Content -Raw -LiteralPath $keeperPath | ConvertFrom-Json
    $keeper = Get-Process -Id $saved.process_id -ErrorAction SilentlyContinue
    if ($keeper -and $keeper.ProcessName -eq 'wsl' -and $keeper.StartTime.ToUniversalTime().Ticks.ToString() -eq $saved.start_ticks) {
        Stop-Process -Id $keeper.Id
    }
    Remove-Item -LiteralPath $keeperPath
}
