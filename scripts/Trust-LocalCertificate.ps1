. "$PSScriptRoot/Common.ps1"
$certificatePath = Join-Path $script:ProjectRoot 'certificates/BartaLAN-Root-CA.cer'
if (!(Test-Path -LiteralPath $certificatePath)) { throw 'Start the server once to generate its local certificate.' }
$certificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2 $certificatePath
if (!(Test-Path -LiteralPath "Cert:/CurrentUser/Root/$($certificate.Thumbprint)")) {
    Import-Certificate -FilePath $certificatePath -CertStoreLocation Cert:/CurrentUser/Root | Out-Null
}
Write-Host 'This Windows account now trusts the BartaLAN local CA. Install the public CA certificate separately on each client device.'
