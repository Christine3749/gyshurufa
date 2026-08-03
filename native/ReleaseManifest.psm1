Set-StrictMode -Version Latest

function Get-GYReleaseManifestPath {
  $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  Join-Path $workspaceRoot 'release\release.json'
}

function Get-GYReleaseManifest {
  param([string]$Path = (Get-GYReleaseManifestPath))

  if (-not (Test-Path -LiteralPath $Path)) { throw "Release manifest is missing: $Path" }
  $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  foreach ($property in 'schemaVersion', 'channel', 'version', 'coreVersion', 'hostVersion', 'windows') {
    if (-not $manifest.PSObject.Properties.Name.Contains($property)) { throw "Release manifest field is missing: $property" }
  }
  foreach ($version in @($manifest.version, $manifest.coreVersion, $manifest.hostVersion)) {
    if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Release manifest contains an invalid version: $version" }
  }
  if ($manifest.version -ne $manifest.coreVersion -or $manifest.version -ne $manifest.hostVersion) {
    throw "Release manifest must use one identical version for package, core and Host."
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
