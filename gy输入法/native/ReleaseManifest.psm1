Set-StrictMode -Version Latest

function Get-GYReleaseManifestPath {
  # Native source can live under gy输入法/ locally or directly at repository root.
  $workspaceManifest = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'release\release.json'
  if (Test-Path -LiteralPath $workspaceManifest) { return $workspaceManifest }
  $rootManifest = Join-Path $PSScriptRoot 'release.json'
  if (Test-Path -LiteralPath $rootManifest) { return $rootManifest }
  throw 'Canonical release/release.json is missing.'
}

function Test-GYVersion([string]$Version) {
  return $Version -match '^\d+\.\d+\.\d+$'
}

function Get-GYReleaseManifest {
  param([string]$Path = (Get-GYReleaseManifestPath))

  $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  foreach ($property in 'schemaVersion', 'releaseId', 'channel', 'windows', 'macos') {
    if (-not $manifest.PSObject.Properties.Name.Contains($property)) { throw "Release manifest field is missing: $property" }
  }
  if ([int]$manifest.schemaVersion -ne 2) { throw "Unsupported release manifest schema: $($manifest.schemaVersion). Expected 2." }
  if ([string]$manifest.channel -notin @('candidate', 'beta', 'stable')) { throw 'Release manifest channel is invalid.' }

  $win = $manifest.windows
  foreach ($property in 'version', 'coreVersion', 'hostVersion', 'setupFile', 'zipFile', 'sha256', 'bytes', 'state', 'architecture') {
    if (-not $win.PSObject.Properties.Name.Contains($property)) { throw "Release manifest windows field is missing: $property" }
  }
  foreach ($version in @($win.version, $win.coreVersion, $win.hostVersion)) {
    if (-not (Test-GYVersion ([string]$version))) { throw "Windows release has invalid version: $version" }
  }
  if ($win.version -ne $win.coreVersion -or $win.version -ne $win.hostVersion) { throw 'Windows package, core, and Host versions must be identical.' }
  if ([string]$win.architecture -ne 'x64') { throw 'Windows release architecture must be x64.' }
  if ($win.setupFile -ne "GYInputSetup-$($win.version).exe") { throw 'Windows setupFile does not match its version.' }
  if ($win.zipFile -ne "GYInput-$($win.version).zip") { throw 'Windows zipFile does not match its version.' }
  if ([string]$win.state -eq 'draft') {
    if ($win.sha256 -ne 'PENDING-PACKAGE-VERIFICATION' -or [Int64]$win.bytes -ne 0) { throw 'Draft Windows release must have pending hash and zero bytes.' }
  } else {
    if ([string]$win.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [Int64]$win.bytes -le 0) { throw 'Published Windows release hash/bytes are invalid.' }
  }

  $nativeVersion = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
  if ($nativeVersion -ne $win.version) { throw "Native VERSION ($nativeVersion) does not match Windows release version ($($win.version))." }

  $mac = $manifest.macos
  foreach ($property in 'version', 'state', 'architecture') {
    if (-not $mac.PSObject.Properties.Name.Contains($property)) { throw "Release manifest macOS field is missing: $property" }
  }
  if (-not (Test-GYVersion ([string]$mac.version))) { throw "macOS release has invalid version: $($mac.version)" }
  if ([string]$mac.architecture -ne 'arm64') { throw 'macOS release architecture must be arm64.' }
  if ([string]$mac.state -notin @('verification-required', 'candidate', 'signed', 'notarized', 'stable')) { throw 'macOS release state is invalid.' }
  if ([string]$mac.state -in @('candidate', 'signed', 'notarized', 'stable')) {
    foreach ($property in 'packageFile', 'sha256', 'bytes', 'signed', 'notarized') {
      if (-not $mac.PSObject.Properties.Name.Contains($property)) { throw "Published macOS release field is missing: $property" }
    }
    if ($mac.packageFile -ne "GYInput-$($mac.version)-arm64.pkg") { throw 'macOS packageFile does not match its version.' }
    if ([string]$mac.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [Int64]$mac.bytes -le 0) { throw 'macOS hash/bytes are invalid.' }
  }
  return $manifest
}

function Assert-GYReleaseVersion {
  param($Manifest, [string]$RequestedVersion)
  $version = [string]$Manifest.windows.version
  if ($RequestedVersion -and $RequestedVersion -ne $version) { throw "Requested Windows version $RequestedVersion does not match canonical Windows version $version." }
  return $version
}

Export-ModuleMember -Function Get-GYReleaseManifestPath, Get-GYReleaseManifest, Assert-GYReleaseVersion