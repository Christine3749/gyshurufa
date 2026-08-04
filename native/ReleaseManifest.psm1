Set-StrictMode -Version Latest

function Get-GYReleaseManifestPath {
  # Local development keeps native/ under gy输入法/, while the GitHub release
  # repository has native/ directly under its root. Resolve both layouts so
  # local builds and clean GitHub clones share one canonical manifest.
  $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  $workspaceManifest = Join-Path $workspaceRoot 'release\release.json'
  if (Test-Path -LiteralPath $workspaceManifest) { return $workspaceManifest }

  $repositoryRoot = Split-Path -Parent $PSScriptRoot
  $repositoryManifest = Join-Path $repositoryRoot 'release\release.json'
  if (Test-Path -LiteralPath $repositoryManifest) { return $repositoryManifest }

  return $workspaceManifest
}

function Get-GYReleaseManifest {
  param([string]$Path = (Get-GYReleaseManifestPath))

  if (-not (Test-Path -LiteralPath $Path)) { throw "Release manifest is missing: $Path" }
  $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  foreach ($property in 'schemaVersion', 'channel', 'version', 'coreVersion', 'hostVersion', 'windows', 'macos') {
    if (-not $manifest.PSObject.Properties.Name.Contains($property)) { throw "Release manifest field is missing: $property" }
  }
  if ([int]$manifest.schemaVersion -ne 1) { throw "Unsupported release manifest schema: $($manifest.schemaVersion)" }
  if ([string]$manifest.channel -notin @('candidate', 'beta', 'stable')) {
    throw "Release manifest channel must be candidate, beta, or stable: $($manifest.channel)"
  }
  foreach ($version in @($manifest.version, $manifest.coreVersion, $manifest.hostVersion)) {
    if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Release manifest contains an invalid version: $version" }
  }
  if ($manifest.version -ne $manifest.coreVersion -or $manifest.version -ne $manifest.hostVersion) {
    throw "Release manifest must use one identical version for package, core and Host."
  }
  foreach ($property in 'setupFile', 'zipFile', 'sha256', 'bytes', 'state') {
    if (-not $manifest.windows.PSObject.Properties.Name.Contains($property)) { throw "Release manifest windows field is missing: $property" }
  }
  if ($manifest.windows.setupFile -ne "GYInputSetup-$($manifest.version).exe") {
    throw "Release manifest setupFile must match the canonical version."
  }
  if ($manifest.windows.zipFile -ne "GYInput-$($manifest.version).zip") {
    throw "Release manifest zipFile must match the canonical version."
  }
  $isDraft = [string]$manifest.windows.state -eq 'draft'
  if ($isDraft) {
    if ($manifest.windows.sha256 -ne 'PENDING-PACKAGE-VERIFICATION' -or [Int64]$manifest.windows.bytes -ne 0) {
      throw 'A draft release must use PENDING-PACKAGE-VERIFICATION and bytes=0.'
    }
  } else {
    if ([string]$manifest.windows.sha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'Published/candidate release SHA-256 must be a 64-character hex string.' }
    if ([Int64]$manifest.windows.bytes -le 0) { throw 'Published/candidate release bytes must be greater than zero.' }
  }
  $nativeVersionPath = Join-Path $PSScriptRoot 'VERSION'
  if (-not (Test-Path -LiteralPath $nativeVersionPath)) { throw "Native VERSION file is missing: $nativeVersionPath" }
  $nativeVersion = (Get-Content -LiteralPath $nativeVersionPath -Raw).Trim()
  if ($nativeVersion -ne $manifest.version) {
    throw "Native VERSION ($nativeVersion) does not match canonical release.json version ($($manifest.version))."
  }
  if (-not $manifest.macos.PSObject.Properties.Name.Contains('state')) { throw 'Release manifest macOS state is missing.' }
  $macState = [string]$manifest.macos.state
  if ($macState -notin @('verification-required', 'candidate', 'verified', 'notarized', 'stable')) {
    throw "Release manifest macOS state is invalid: $macState"
  }
  if ($macState -in @('notarized', 'stable')) {
    foreach ($property in 'packageFile', 'sha256', 'bytes', 'signed', 'notarized') {
      if (-not $manifest.macos.PSObject.Properties.Name.Contains($property)) { throw "Release manifest macOS field is missing: $property" }
    }
    if ([string]$manifest.macos.packageFile -ne "GYInput-$($manifest.version)-arm64.pkg") { throw 'Release manifest macOS package file does not match canonical version.' }
    if ([string]$manifest.macos.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [Int64]$manifest.macos.bytes -le 0) { throw 'Release manifest macOS hash/bytes are invalid.' }
    if (-not [bool]$manifest.macos.signed -or -not [bool]$manifest.macos.notarized) { throw 'Notarized macOS release metadata must confirm signing and notarization.' }
  }
  $manifest
}

function Assert-GYReleaseVersion {
  param($Manifest, [string]$RequestedVersion)

  if ($RequestedVersion -and $RequestedVersion -ne $Manifest.version) {
    throw "Requested version $RequestedVersion does not match canonical release version $($Manifest.version)."
  }
  $Manifest.version
}

Export-ModuleMember -Function Get-GYReleaseManifestPath, Get-GYReleaseManifest, Assert-GYReleaseVersion