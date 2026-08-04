[CmdletBinding()]
param(
  [string]$Version,
  [string]$ReleaseRoot = (Join-Path $PSScriptRoot 'release')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ReleaseManifest.psm1') -Force
$manifestPath = Get-GYReleaseManifestPath
$manifest = Get-GYReleaseManifest
$Version = Assert-GYReleaseVersion -Manifest $manifest -RequestedVersion $Version

$packageRoot = Join-Path $ReleaseRoot "GYInput-$Version"
$packageManifest = Join-Path $packageRoot 'release.json'
$setup = Join-Path $ReleaseRoot "GYInputSetup-$Version.exe"
$zip = Join-Path $ReleaseRoot "GYInput-$Version.zip"
if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) { throw "Package directory is missing: $packageRoot" }
if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) { throw "Installer is missing: $setup. Run build-installer.ps1 first." }

# Windows and macOS have independent product versions. A Mac package still in
# verification must never block a verified Windows candidate or be advertised.
if (Test-Path -LiteralPath $zip -PathType Leaf) { throw "ZIP output already exists: $zip. Never overwrite a published version; create a new version instead." }

# The installer is immutable once this step succeeds. A later code change must
# use a new version, never overwrite this metadata or its version directory.
$manifest.windows.sha256 = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash
$manifest.windows.bytes = (Get-Item -LiteralPath $setup).Length
if ([string]$manifest.windows.state -eq 'draft') {
  $manifest.windows.state = if ([string]$manifest.channel -eq 'stable') { 'awaiting-signature' } else { 'candidate' }
}
$manifest.publishedAtUtc = [DateTime]::UtcNow.ToString("o")
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Copy-Item -LiteralPath $manifestPath -Destination $packageManifest -Force

Compress-Archive -LiteralPath $packageRoot -DestinationPath $zip -CompressionLevel Optimal
$setupHash = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash
Set-Content -LiteralPath "$setup.sha256" -Value "$setupHash  $(Split-Path -Leaf $setup)" -NoNewline -Encoding ascii

& (Join-Path $PSScriptRoot 'installer\Verify-GYRelease.ps1') -Version $Version -ReleaseRoot $ReleaseRoot
Write-Host "Release metadata finalized for $Version. It is not published until Publish-GYRelease.ps1 completes." -ForegroundColor Green
