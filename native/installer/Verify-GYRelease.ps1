[CmdletBinding()]
param(
  [string]$Version,
  [string]$ReleaseRoot = (Join-Path $PSScriptRoot '..\release'),
  [switch]$RequireSignature
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\ReleaseManifest.psm1') -Force
$releaseDefinition = Get-GYReleaseManifest
$Version = Assert-GYReleaseVersion -Manifest $releaseDefinition -RequestedVersion $Version
$packageRoot = Join-Path $ReleaseRoot "GYInput-$Version"
$payloadRoot = Join-Path $packageRoot 'payload'
$setup = Join-Path $ReleaseRoot "GYInputSetup-$Version.exe"
$zip = Join-Path $ReleaseRoot "GYInput-$Version.zip"
$hashManifest = Join-Path $payloadRoot 'SHA256SUMS.txt'
$packageReleaseDefinition = Join-Path $packageRoot 'release.json'
$failures = [Collections.Generic.List[string]]::new()

function Fail([string]$message) { Write-Host "[FAIL] $message" -ForegroundColor Red; $failures.Add($message) }
function Pass([string]$message) { Write-Host "[PASS] $message" -ForegroundColor Green }

if (-not (Test-Path -LiteralPath $hashManifest -PathType Leaf)) { Fail 'Payload SHA-256 manifest is missing.' }
else {
  foreach ($line in Get-Content -LiteralPath $hashManifest) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line -split '  ', 2
    if ($parts.Count -ne 2) { Fail "Malformed SHA-256 manifest line: $line"; continue }
    $file = Join-Path $payloadRoot $parts[1]
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Fail "Payload file is missing: $($parts[1])"; continue }
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $parts[0]) { Fail "Payload hash mismatch: $($parts[1])" }
  }
  if ($failures.Count -eq 0) { Pass 'Payload SHA-256 manifest matches every packaged file.' }
}

if (-not (Test-Path -LiteralPath $packageReleaseDefinition -PathType Leaf)) { Fail 'Package release.json is missing.' }
else {
  try {
    $packageDefinition = Get-Content -LiteralPath $packageReleaseDefinition -Raw | ConvertFrom-Json
    if ($packageDefinition.version -ne $Version -or $packageDefinition.coreVersion -ne $Version -or $packageDefinition.hostVersion -ne $Version) {
      Fail "Package release.json is inconsistent: package/core/host must all equal $Version."
    } else {
      Pass "Package release.json matches package/core/host version $Version."
    }
  } catch { Fail "Package release.json cannot be parsed: $($_.Exception.Message)" }
}

$targets = @(
  (Join-Path $payloadRoot "GyIme-$Version.dll"),
  (Join-Path $payloadRoot "GyImeHost-$Version.exe"),
  (Join-Path $payloadRoot "GyImeHealth-$Version.exe"),
  $setup
)
foreach ($target in $targets) {
  if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { Fail "Release binary is missing: $target"; continue }
  $signature = Get-AuthenticodeSignature -LiteralPath $target
  $label = Split-Path -Leaf $target
  if ($signature.Status -eq 'Valid') { Pass "Authenticode valid: $label ($($signature.SignerCertificate.Subject))" }
  elseif ($RequireSignature) { Fail "Authenticode must be Valid for public Beta: $label ($($signature.Status))" }
  else { Write-Host "[INFO] Internal-build signature state: $label ($($signature.Status))" -ForegroundColor Yellow }
}

if (-not (Test-Path -LiteralPath $zip -PathType Leaf)) { Fail "ZIP archive is missing: $zip" }
else { Pass "ZIP archive present: $(Split-Path -Leaf $zip)" }
if ($failures.Count) { throw "GY release verification failed: $($failures.Count) problem(s)." }
Write-Host "GY release verification passed for $Version." -ForegroundColor Green
