[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Version,
  [string]$ReleaseRoot = (Join-Path $PSScriptRoot 'release'),
  [string]$BucketName = 'gy-shurufa-releases',
  [switch]$AllowUnsignedCandidate
)

$ErrorActionPreference = 'Stop'

# PS 5.1 turns any native stderr line (for example wrangler proxy warnings)
# into a terminating NativeCommandError while Stop is in effect. Run native
# CLI calls under Continue and rely on explicit $LASTEXITCODE checks instead.
function Invoke-ReleaseNative {
  param([scriptblock]$Command)
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { & $Command } finally { $ErrorActionPreference = $previousPreference }
}
Import-Module (Join-Path $PSScriptRoot 'ReleaseManifest.psm1') -Force
$manifestPath = Get-GYReleaseManifestPath
$manifest = Get-GYReleaseManifest
$Version = Assert-GYReleaseVersion -Manifest $manifest -RequestedVersion $Version

if ([string]$manifest.windows.state -eq 'draft') { throw 'Draft Windows releases must be finalized before publishing.' }
$requireSignature = [string]$manifest.channel -eq 'stable'
if (-not $requireSignature -and -not $AllowUnsignedCandidate) {
  throw 'This pipeline requires Authenticode for all published builds by default; use -AllowUnsignedCandidate only for temporary internal candidate publishing.'
}

& (Join-Path $PSScriptRoot 'installer\Verify-GYRelease.ps1') -Version $Version -ReleaseRoot $ReleaseRoot -RequireSignature:$requireSignature

$setup = Join-Path $ReleaseRoot $manifest.windows.setupFile
$zip = Join-Path $ReleaseRoot $manifest.windows.zipFile
$setupHash = "$setup.sha256"
$packageManifest = Join-Path (Join-Path $ReleaseRoot "GYInput-$Version") 'release.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "GYReleasePublish-$Version-$PID"
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
  $prefix = "releases/$Version/windows"
  function Assert-R2ObjectAbsent([string]$ObjectKey) {
    $probe = Join-Path $tempRoot ([IO.Path]::GetRandomFileName())
    Invoke-ReleaseNative { & npx wrangler r2 object get "$BucketName/$ObjectKey" --file "$probe" --remote 2>$null }
    if ($LASTEXITCODE -eq 0) { throw "Refusing to overwrite immutable published object: $ObjectKey" }
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
  }
  function Put-Immutable([string]$LocalPath, [string]$ObjectKey, [string]$ContentType = '') {
    if (-not (Test-Path -LiteralPath $LocalPath -PathType Leaf)) { throw "Release file is missing: $LocalPath" }
    if ($PSCmdlet.ShouldProcess("$BucketName/$ObjectKey", 'Upload immutable verified release object')) {
      Assert-R2ObjectAbsent $ObjectKey
      $wranglerArgs = @('wrangler','r2','object','put',"$BucketName/$ObjectKey",'--file',$LocalPath)
      if ($ContentType) { $wranglerArgs += @('--content-type',$ContentType) }
      $wranglerArgs += '--remote'
      Invoke-ReleaseNative { & npx @wranglerArgs }
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
    Invoke-ReleaseNative { & npx wrangler r2 object get "$BucketName/$prefix/$($manifest.windows.setupFile)" --file "$remoteWindows" --remote }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $remoteWindows -PathType Leaf)) {
      throw 'Verified Windows package is not present in R2; latest remains unchanged.'
    }
    $remoteWindowsHash = (Get-FileHash -LiteralPath $remoteWindows -Algorithm SHA256).Hash
    if ($remoteWindowsHash -ne [string]$manifest.windows.sha256 -or (Get-Item -LiteralPath $remoteWindows).Length -ne [Int64]$manifest.windows.bytes) {
      throw 'R2 Windows package hash/size does not match canonical release.json; latest remains unchanged.'
    }
  }
  if ($PSCmdlet.ShouldProcess("$BucketName/releases/latest.json", 'Atomically advance verified cross-platform latest pointer')) {
    Invoke-ReleaseNative { & npx wrangler r2 object put "$BucketName/releases/latest.json" --file "$manifestPath" --content-type 'application/json; charset=utf-8' --remote }
    if ($LASTEXITCODE -ne 0) { throw 'Unable to advance releases/latest.json.' }
  }
  Write-Host "Published verified Windows release $Version and atomically advanced releases/latest.json. macOS state remains exactly as recorded in the contract." -ForegroundColor Green
}
finally {
  Remove-Item -LiteralPath $tempRoot -Force -Recurse -ErrorAction SilentlyContinue
}



