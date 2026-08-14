[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Version,
  [Parameter(Mandatory)][string]$CertificateThumbprint,
  [Parameter(Mandatory)][string]$TimestampServer,
  [string]$ReleaseRoot = (Join-Path $PSScriptRoot '..\release'),
  [string]$ApprovalPath = ''
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\ReleaseManifest.psm1') -Force
$manifestPath = Get-GYReleaseManifestPath
$manifest = Get-GYReleaseManifest
$Version = Assert-GYReleaseVersion -Manifest $manifest -RequestedVersion $Version
if ($ApprovalPath) { $approval = Assert-GYReleaseApproval -Manifest $manifest -Version $Version -ApprovalPath $ApprovalPath }
else { $approval = Assert-GYReleaseApproval -Manifest $manifest -Version $Version }
if ($TimestampServer -notmatch '^https://') { throw 'A public-Beta signature requires an HTTPS RFC 3161 timestamp server.' }
$thumbprint = ($CertificateThumbprint -replace '\s', '').ToUpperInvariant()
$certificate = Get-ChildItem -Path "Cert:\CurrentUser\My\$thumbprint" -ErrorAction SilentlyContinue
if (-not $certificate) { throw "No signing certificate with thumbprint $thumbprint exists in Cert:\CurrentUser\My." }
if (-not $certificate.HasPrivateKey) { throw 'The selected certificate has no accessible private key.' }
if ($certificate.NotAfter -le (Get-Date)) { throw 'The selected certificate is expired.' }

$packageRoot = Join-Path $ReleaseRoot "GYInput-$Version"
$payloadRoot = Join-Path $packageRoot 'payload'
$setup = Join-Path $ReleaseRoot "GYInputSetup-$Version.exe"
$zip = Join-Path $ReleaseRoot "GYInput-$Version.zip"
if (Test-Path -LiteralPath $zip -PathType Leaf) { throw "Refusing to sign or overwrite an existing ZIP: $zip. Bump the version." }
$targets = @(
  (Join-Path $payloadRoot "GyIme-$Version.dll"),
  (Join-Path $payloadRoot "GyImeHost-$Version.exe"),
  (Join-Path $payloadRoot "GyImeHealth-$Version.exe")
)
foreach ($target in $targets) {
  if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Release binary is missing: $target" }
}

function Sign-Target([string]$Target) {
  if ($PSCmdlet.ShouldProcess($Target, 'Apply Authenticode signature')) {
    $signature = Set-AuthenticodeSignature -LiteralPath $Target -Certificate $certificate -TimestampServer $TimestampServer -HashAlgorithm SHA256
    if ($signature.Status -ne 'Valid') { throw "Signing failed for ${Target}: $($signature.Status) $($signature.StatusMessage)" }
  }
}

foreach ($target in $targets) { Sign-Target $target }
if ($WhatIfPreference) { return }

$hashLines = Get-ChildItem -LiteralPath $payloadRoot -File -Recurse | Where-Object { $_.Name -ne 'SHA256SUMS.txt' } | ForEach-Object {
  $relative = $_.FullName.Substring($payloadRoot.Length + 1)
  "{0}  {1}" -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, $relative
}
Set-Content -LiteralPath (Join-Path $payloadRoot 'SHA256SUMS.txt') -Value $hashLines -Encoding utf8

& (Join-Path $PSScriptRoot '..\build-installer.ps1') -Version $Version -ApprovalPath $ApprovalPath
if ($LASTEXITCODE -ne 0) { throw 'Installer rebuild failed after signing the payload.' }
Sign-Target $setup

$manifest.windows.sha256 = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash
$manifest.windows.bytes = (Get-Item -LiteralPath $setup).Length
$manifest.windows.signed = $true
if ([string]$manifest.windows.state -eq 'draft') {
  $manifest.windows.state = if ([string]$manifest.channel -eq 'stable') { 'signed' } else { 'candidate' }
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $packageRoot 'release.json') -Force

# Finalize builds the ZIP once, only after the Mac asset has updated the same manifest.
& (Join-Path $PSScriptRoot '..\Finalize-GYRelease.ps1') -Version $Version -ReleaseRoot $ReleaseRoot -ApprovalPath $ApprovalPath
if ($LASTEXITCODE -ne 0) { throw 'Final cross-platform release finalization failed.' }
& (Join-Path $PSScriptRoot 'Verify-GYRelease.ps1') -Version $Version -ReleaseRoot $ReleaseRoot -RequireSignature -ApprovalPath $ApprovalPath
if ($LASTEXITCODE -ne 0) { throw 'Public release signature verification failed.' }
Write-Host "Signed immutable cross-platform release created: $setup" -ForegroundColor Green
