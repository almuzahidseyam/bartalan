# Download through Windows when WSL itself cannot reach internet registries.
[CmdletBinding()]
param([switch]$UseCachedArchives)
. "$PSScriptRoot/Common.ps1"
$cache = Join-Path $script:ProjectRoot '.runtime'
New-Item -ItemType Directory -Force -Path $cache | Out-Null
$tool = Join-Path $cache 'crane.exe'
$release = 'https://github.com/google/go-containerregistry/releases/download/v0.22.1'
if (!(Test-Path -LiteralPath $tool)) {
    $archive = Join-Path $cache 'crane.tar.gz'
    $checksumsPath = Join-Path $cache 'crane-checksums.txt'
    Invoke-WebRequest -UseBasicParsing "$release/checksums.txt" -OutFile $checksumsPath
    Invoke-WebRequest -UseBasicParsing "$release/go-containerregistry_Windows_x86_64.tar.gz" -OutFile $archive
    $expectedLine = Get-Content -LiteralPath $checksumsPath | Where-Object {$_ -match ' go-containerregistry_Windows_x86_64.tar.gz$'}
    if (!$expectedLine) { throw 'Crane release checksum not found.' }
    $expected = ($expectedLine.Trim() -split '\s+')[0]
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'Crane checksum mismatch.' }
    & tar.exe -xf $archive -C $cache crane.exe
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract the image download tool.' }
}
$envPath = Join-Path $script:ProjectRoot '.env'
$privateConfig = [IO.File]::ReadAllText($envPath)
$linuxPath = Get-LinuxProjectPath
$lock = @{}
foreach ($key in @('MATTERMOST_IMAGE', 'POSTGRES_IMAGE', 'GATEWAY_IMAGE')) {
    $sourceLine = Get-Content -LiteralPath (Join-Path $script:ProjectRoot '.env.example') | Where-Object {$_ -match "^${key}="}
    $source = $sourceLine.Substring($key.Length + 1)
    if ($source -notmatch '@sha256:[a-f0-9]{64}$') { throw 'The template must pin a registry manifest digest.' }
    $name = switch ($key) {'MATTERMOST_IMAGE' {'mattermost'} 'POSTGRES_IMAGE' {'postgres'} 'GATEWAY_IMAGE' {'gateway'}}
    $tarPath = Join-Path $cache "$name.tar"
    Write-Host "Downloading verified $name image using Windows networking."
    $manifestJson = (& $tool manifest $source --platform linux/amd64 | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'Could not retrieve the pinned image manifest.' }
    $manifest = $manifestJson | ConvertFrom-Json
    $configId = $manifest.config.digest
    if ($configId -notmatch '^sha256:[a-f0-9]{64}$') { throw 'Invalid image configuration digest.' }
    # crane verifies registry content digests while reading the image layers.
    if (!$UseCachedArchives) {
        & $tool pull $source $tarPath --platform linux/amd64
        if ($LASTEXITCODE -ne 0) { throw "$name image download failed." }
    } elseif (!(Test-Path -LiteralPath $tarPath)) { throw "Missing cached archive: $name.tar" }
    $archiveManifest = ((& tar.exe -xOf $tarPath manifest.json | Out-String) | ConvertFrom-Json)[0]
    if ($archiveManifest.Config -ne $configId) { throw 'Archive configuration does not match the pinned manifest.' }
    $archiveConfig = (& tar.exe -xOf $tarPath $configId | Out-String) | ConvertFrom-Json
    & wsl.exe -d $script:Distro -u root --exec docker image load --input "$linuxPath/.runtime/$name.tar"
    if ($LASTEXITCODE -ne 0) { throw "$name image import failed." }
    $loaded = ((& wsl.exe -d $script:Distro -u root --exec docker image inspect $archiveManifest.RepoTags[0] | Out-String) | ConvertFrom-Json)[0]
    if ($LASTEXITCODE -ne 0) { throw 'Imported image cannot be inspected.' }
    if (($loaded.RootFS.Layers -join ',') -ne ($archiveConfig.rootfs.diff_ids -join ',')) { throw 'Loaded image filesystem does not match the verified archive.' }
    foreach ($field in @('User','Env','Cmd','Entrypoint','WorkingDir','StopSignal')) {
        $expectedField = $archiveConfig.config.$field | ConvertTo-Json -Compress -Depth 10
        $actualField = $loaded.Config.$field | ConvertTo-Json -Compress -Depth 10
        if ($expectedField -ne $actualField) { throw "Loaded image $field does not match the verified archive." }
    }
    $imageId = $loaded.Id
    if ($imageId -notmatch '^sha256:[a-f0-9]{64}$') { throw 'Invalid local image ID.' }
    # Docker may convert legacy manifests while importing. Pin its verified local ID.
    $privateConfig = [regex]::Replace($privateConfig, "(?m)^${key}=.*$", "${key}=$imageId")
    $lock[$key] = @{source=$source; configuration_digest=$configId; local_image_id=$imageId; archive_sha256=(Get-FileHash -LiteralPath $tarPath -Algorithm SHA256).Hash.ToLowerInvariant()}
}
[IO.File]::WriteAllText($envPath, $privateConfig, (New-Object Text.UTF8Encoding $false))
$lock | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $cache 'image-lock.json') -Encoding UTF8
Protect-BartaSecrets
Write-Host 'Pinned images are cached. Start.ps1 can now run without internet.'
