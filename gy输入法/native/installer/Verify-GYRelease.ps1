[CmdletBinding()]
param(
  [string]$Version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\VERSION') -Raw).Trim(),
  [string]$ReleaseRoot = (Join-Path $PSScriptRoot '..\release'),
  [switch]$RequireSignature
)

$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Version must use major.minor.patch format.' }
$packageRoot = Join-Path $ReleaseRoot "GYInput-$Version"
$payloadRoot = Join-Path $packageRoot 'payload'
$setup = Join-Path $ReleaseRoot "GYInputSetup-$Version.exe"
$zip = Join-Path $ReleaseRoot "GYInput-$Version.zip"
$manifest = Join-Path $payloadRoot 'SHA256SUMS.txt'
$failures = [Collections.Generic.List[string]]::new()

function Fail([string]$message) { Write-Host "[FAIL] $message" -ForegroundColor Red; $failures.Add($message) }
function Pass([string]$message) { Write-Host "[PASS] $message" -ForegroundColor Green }

if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { Fail 'Payload SHA-256 manifest is missing.' }
else {
  foreach ($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line -split '  ', 2
    if ($parts.Count -ne 2) { Fail "Malformed SHA-256 manifest line: $line"; continue }
    $file = Join-Path $payloadRoot $parts[1]
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Fail "Payload file is missing: $($parts[1])"; continue }
    $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    if ($actual -ne $parts[0]) { Fail "Payload hash mismatch: $($parts[1])" }
  }
  if ($failures.Count -eq 0) { Pass 'Payload SHA-256 manifest matches every packaged file.' }
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