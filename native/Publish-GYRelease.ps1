[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Version,
  [string]$ReleaseRoot = (Join-Path $PSScriptRoot 'release'),
  [string]$BucketName = 'gy-shurufa-releases',
  [switch]$AllowUnsignedCandidate
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ReleaseManifest.psm1') -Force
$manifestPath = Get-GYReleaseManifestPath
$manifest = Get-GYReleaseManifest
$Version = Assert-GYReleaseVersion -Manifest $manifest -RequestedVersion $Version

if ([string]$manifest.windows.state -eq 'draft') { throw 'Draft Windows releases must be finalized before publishing.' }
$requireSignature = [string]$manifest.channel -eq 'stable'
if (-not $requireSignature -and -not $AllowUnsignedCandidate) {
  throw 'Candidate publication requires -AllowUnsignedCandidate. Stable publication always requires Authenticode.'
}

$mac = $manifest.macos
if (-not $mac) { throw 'macOS release metadata is missing. Windows-only latest pointers are forbidden.' }
$expectedMacFile = "GYInput-$Version-arm64.pkg"
if ([string]$mac.packageFile -ne $expectedMacFile) { throw "Mac package filename must be $expectedMacFile." }
if ([string]$mac.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [Int64]$mac.bytes -le 0) { throw 'Mac package hash/bytes are not verified.' }
if (-not [bool]$mac.signed -or -not [bool]$mac.notarized -or [string]$mac.state -notin @('notarized', 'stable')) {
  throw 'Mac package is not signed, notarized, and verified. Public latest cannot advance.'
}

& (Join-Path $PSScriptRoot 'installer\Verify-GYRelease.ps1') -Version $Version -ReleaseRoot $ReleaseRoot -RequireSignature:$requireSignature
if ($LASTEXITCODE -ne 0) { throw 'Windows release verification failed; nothing was uploaded and latest was not changed.' }

$setup = Join-Path $ReleaseRoot $manifest.windows.setupFile
$zip = Join-Path $ReleaseRoot $manifest.windows.zipFile
$setupHash = "$setup.sha256"
$packageManifest = Join-Path (Join-Path $ReleaseRoot "GYInput-$Version") 'release.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "GYReleasePublish-$Version-$PID"
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
  $macObjectKey = "releases/$Version/macos/$expectedMacFile"
  $remoteMac = Join-Path $tempRoot $expectedMacFile
  if ($PSCmdlet.ShouldProcess("$BucketName/$macObjectKey", 'Download and hash-verify already uploaded Mac release')) {
    & npx wrangler r2 object get "$BucketName/$macObjectKey" --file "$remoteMac"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $remoteMac -PathType Leaf)) { throw 'Verified Mac package is not present in R2; latest remains unchanged.' }
    $macHash = (Get-FileHash -LiteralPath $remoteMac -Algorithm SHA256).Hash
    if ($macHash -ne [string]$mac.sha256 -or (Get-Item -LiteralPath $remoteMac).Length -ne [Int64]$mac.bytes) {
      throw 'R2 Mac package hash/size does not match canonical release.json; latest remains unchanged.'
    }
  }

  $prefix = "releases/$Version/windows"
  function Assert-R2ObjectAbsent([string]$ObjectKey) {
    $probe = Join-Path $tempRoot ([IO.Path]::GetRandomFileName())
    & npx wrangler r2 object get "$BucketName/$ObjectKey" --file "$probe" 2>$null
    if ($LASTEXITCODE -eq 0) { throw "Refusing to overwrite immutable published object: $ObjectKey" }
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
  }
  function Put-Immutable([string]$LocalPath, [string]$ObjectKey, [string]$ContentType = '') {
    if (-not (Test-Path -LiteralPath $LocalPath -PathType Leaf)) { throw "Release file is missing: $LocalPath" }
    if ($PSCmdlet.ShouldProcess("$BucketName/$ObjectKey", 'Upload immutable verified release object')) {
      Assert-R2ObjectAbsent $ObjectKey
      $args = @('wrangler','r2','object','put',"$BucketName/$ObjectKey",'--file',$LocalPath)
      if ($ContentType) { $args += @('--content-type',$ContentType) }
      & npx @args
      if ($LASTEXITCODE -ne 0) { throw "R2 upload failed: $ObjectKey" }
    }
  }

  # Versioned objects first. latest.json is the only mutable pointer and is written last.
  Put-Immutable $setup "$prefix/$($manifest.windows.setupFile)" 'application/vnd.microsoft.portable-executable'
  Put-Immutable $zip "$prefix/$($manifest.windows.zipFile)" 'application/zip'
  Put-Immutable $setupHash "$prefix/$($manifest.windows.setupFile).sha256" 'text/plain; charset=utf-8'
  Put-Immutable $packageManifest "releases/$Version/release.json" 'application/json; charset=utf-8'
  if ($PSCmdlet.ShouldProcess("$BucketName/$prefix/$($manifest.windows.setupFile)", 'Download and hash-verify uploaded Windows release')) {
    $remoteWindows = Join-Path $tempRoot $manifest.windows.setupFile
    & npx wrangler r2 object get "$BucketName/$prefix/$($manifest.windows.setupFile)" --file "$remoteWindows"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $remoteWindows -PathType Leaf)) {
      throw 'Verified Windows package is not present in R2; latest remains unchanged.'
    }
    $remoteWindowsHash = (Get-FileHash -LiteralPath $remoteWindows -Algorithm SHA256).Hash
    if ($remoteWindowsHash -ne [string]$manifest.windows.sha256 -or (Get-Item -LiteralPath $remoteWindows).Length -ne [Int64]$manifest.windows.bytes) {
      throw 'R2 Windows package hash/size does not match canonical release.json; latest remains unchanged.'
    }
  }
  if ($PSCmdlet.ShouldProcess("$BucketName/releases/latest.json", 'Atomically advance verified cross-platform latest pointer')) {
    & npx wrangler r2 object put "$BucketName/releases/latest.json" --file "$manifestPath" --content-type 'application/json; charset=utf-8'
    if ($LASTEXITCODE -ne 0) { throw 'Unable to advance releases/latest.json.' }
  }
  Write-Host "Published verified Windows + macOS release $Version and atomically advanced releases/latest.json." -ForegroundColor Green
}
finally {
  Remove-Item -LiteralPath $tempRoot -Force -Recurse -ErrorAction SilentlyContinue
}
