[CmdletBinding()]
param(
    [string]$SiteUrl = '',
    [ValidateRange(1024,65535)][int]$AppPort = 18065,
    [ValidateSet('127.0.0.1', '0.0.0.0')][string]$BindAddress = '127.0.0.1'
)
. "$PSScriptRoot/Common.ps1"
if (!$SiteUrl) { $SiteUrl = "https://localhost:$AppPort" }
$uri = [Uri]$SiteUrl
if (!$uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or $uri.AbsolutePath -ne '/') {
    throw 'Use a complete HTTPS server URL without a path, for example https://192.168.1.20:18065.'
}
if ($uri.Port -ne $AppPort) { throw 'The server URL port must match -AppPort.' }
if ($env:OS -eq 'Windows_NT') {
    foreach ($rangeLine in (& netsh.exe interface ipv4 show excludedportrange protocol=tcp)) {
        if ($rangeLine -match '^\s*(\d+)\s+(\d+)\s*\*?\s*$' -and $AppPort -ge [int]$matches[1] -and $AppPort -le [int]$matches[2]) {
            throw "Windows has reserved port $AppPort. Choose an available -AppPort and matching -SiteUrl."
        }
    }
}
$envPath = Join-Path $script:ProjectRoot '.env'
if (Test-Path -LiteralPath $envPath) { throw '.env already exists; existing secrets were preserved.' }
$randomBytes = New-Object byte[] 32
$random = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $random.GetBytes($randomBytes) } finally { $random.Dispose() }
$password = -join ($randomBytes | ForEach-Object {$_.ToString('x2')})
$content = [IO.File]::ReadAllText((Join-Path $script:ProjectRoot '.env.example'))
$content = $content.Replace('GENERATE_WITH_INITIALIZE_SCRIPT', $password)
$content = $content.Replace('SITE_URL=https://localhost:18065', "SITE_URL=$($SiteUrl.TrimEnd('/'))")
$content = $content.Replace('APP_PORT=18065', "APP_PORT=$AppPort")
$content = $content.Replace('BIND_ADDRESS=127.0.0.1', "BIND_ADDRESS=$BindAddress")
[IO.File]::WriteAllText($envPath, $content, (New-Object Text.UTF8Encoding $false))
New-Item -ItemType Directory -Force -Path (Join-Path $script:ProjectRoot '.secrets') | Out-Null
Protect-BartaSecrets
Write-Host 'Local configuration and random database password created. Keep .env private.'
