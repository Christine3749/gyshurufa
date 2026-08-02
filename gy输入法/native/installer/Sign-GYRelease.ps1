[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\VERSION') -Raw).Trim(),
  [Parameter(Mandatory)][string]$CertificateThumbprint,
  [Parameter(Mandatory)][string]$TimestampServer,
  [string]$ReleaseRoot = (Join-Path $PSScriptRoot '..\release')
)

$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Version must use major.minor.patch format.' }
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
Compress-Archive -LiteralPath $packageRoot -DestinationPath $zip -CompressionLevel Optimal -Force

& (Join-Path $PSScriptRoot '..\build-installer.ps1') -Version $Version
if ($LASTEXITCODE -ne 0) { throw 'Installer rebuild failed after signing the payload.' }
Sign-Target $setup
$setupHash = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash
$zipHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
Set-Content -LiteralPath "$setup.sha256" -Value "$setupHash  $(Split-Path -Leaf $setup)" -NoNewline -Encoding ascii
Set-Content -LiteralPath "$zip.sha256" -Value "$zipHash  $(Split-Path -Leaf $zip)" -NoNewline -Encoding ascii
& (Join-Path $PSScriptRoot 'Verify-GYRelease.ps1') -Version $Version -ReleaseRoot $ReleaseRoot -RequireSignature
if ($LASTEXITCODE -ne 0) { throw 'Public-Beta signature verification failed.' }
Write-Host "Signed public-Beta release created: $setup" -ForegroundColor Green