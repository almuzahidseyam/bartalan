[CmdletBinding()]
param(
    [string]$SiteUrl = 'http://localhost:8065',
    [ValidateSet('127.0.0.1', '0.0.0.0')][string]$BindAddress = '127.0.0.1'
)
. "$PSScriptRoot/Common.ps1"
$uri = [Uri]$SiteUrl
if (!$uri.IsAbsoluteUri -or $uri.Scheme -notin @('http','https') -or $uri.AbsolutePath -ne '/') {
    throw 'Use a complete server URL without a path, for example http://192.168.1.2:8065.'
}
$envPath = Join-Path $script:ProjectRoot '.env'
if (Test-Path -LiteralPath $envPath) { throw '.env already exists; existing secrets were preserved.' }
$randomBytes = New-Object byte[] 32
$random = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $random.GetBytes($randomBytes) } finally { $random.Dispose() }
$password = -join ($randomBytes | ForEach-Object {$_.ToString('x2')})
$content = [IO.File]::ReadAllText((Join-Path $script:ProjectRoot '.env.example'))
$content = $content.Replace('GENERATE_WITH_INITIALIZE_SCRIPT', $password)
$content = $content.Replace('SITE_URL=http://localhost:8065', "SITE_URL=$($SiteUrl.TrimEnd('/'))")
$content = $content.Replace('BIND_ADDRESS=127.0.0.1', "BIND_ADDRESS=$BindAddress")
[IO.File]::WriteAllText($envPath, $content, (New-Object Text.UTF8Encoding $false))
New-Item -ItemType Directory -Force -Path (Join-Path $script:ProjectRoot '.secrets') | Out-Null
Protect-BartaSecrets
Write-Host 'Local configuration and random database password created. Keep .env private.'
