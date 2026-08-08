[CmdletBinding()]
param(
  [string]$Version,
  [string]$ReleaseRoot,
  [switch]$RequireSignature
)

$ErrorActionPreference = 'Stop'
if (-not $ReleaseRoot) {
  $ReleaseRoot = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\release'
}
Import-Module (Join-Path $PSScriptRoot '..\ReleaseManifest.psm1') -Force
$manifestPath = Get-GYReleaseManifestPath
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
    if ($packageDefinition.windows.version -ne $Version -or $packageDefinition.windows.coreVersion -ne $Version -or $packageDefinition.windows.hostVersion -ne $Version) {
      Fail "Package release.json is inconsistent: Windows package/core/host must all equal $Version."
    } elseif ($packageDefinition.windows.sha256 -ne $releaseDefinition.windows.sha256 -or [Int64]$packageDefinition.windows.bytes -ne [Int64]$releaseDefinition.windows.bytes) {
      Fail 'Package release.json does not match the canonical installer hash and byte size.'
    } else {
      Pass "Package release.json matches Windows package/core/host version $Version and installer metadata."
    }
  } catch { Fail "Package release.json cannot be parsed: $($_.Exception.Message)" }
}

$sourceNotes = Join-Path (Split-Path -Parent $manifestPath) "notes\\$Version.txt"
$packagedNotes = Join-Path $payloadRoot 'release-notes.txt'
if (-not (Test-Path -LiteralPath $sourceNotes -PathType Leaf) -or -not (Test-Path -LiteralPath $packagedNotes -PathType Leaf)) {
  Fail 'Release notes are missing from the canonical source or package.'
} elseif ((Get-FileHash -LiteralPath $sourceNotes -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $packagedNotes -Algorithm SHA256).Hash) {
  Fail 'Packaged release notes differ from the canonical release notes.'
} else {
  Pass "Packaged release notes match canonical release/notes/$Version.txt."
}

$sourceInstallerRoot = $PSScriptRoot
$sourceScripts = @(
  'Install-GYInput.ps1',
  'Validate-GYInput.ps1',
  'Rollback-GYInput.ps1',
  'Repair-GYInput.ps1',
  'Finalize-GYClientReload.ps1',
  'Prune-GYOldVersions.ps1',
  'Register-GYInputActivationTasks.ps1',
  'GYInputTransaction.ps1'
)
foreach ($name in $sourceScripts) {
  $sourcePath = Join-Path $sourceInstallerRoot $name
  $packagePath = Join-Path $packageRoot $name
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -or -not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    Fail "Packaged installer script is missing from source or package: $name"
    continue
  }
  if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash) {
    Fail "Packaged installer script differs from the audited source: $name"
  } else {
    Pass "Packaged installer script matches source: $name"
  }
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
  elseif ($RequireSignature) { Fail "Authenticode must be Valid for a stable public release: $label ($($signature.Status))" }
  else { Write-Host "[INFO] Candidate signature state: $label ($($signature.Status))" -ForegroundColor Yellow }
}

if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) { Fail "Installer is missing: $setup" }
else {
  $actualHash = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash
  $actualBytes = (Get-Item -LiteralPath $setup).Length
  if ($actualHash -ne $releaseDefinition.windows.sha256) { Fail "Installer SHA-256 does not match canonical release.json: expected $($releaseDefinition.windows.sha256), got $actualHash." }
  elseif ([Int64]$actualBytes -ne [Int64]$releaseDefinition.windows.bytes) { Fail "Installer byte size does not match canonical release.json: expected $($releaseDefinition.windows.bytes), got $actualBytes." }
  else { Pass 'Installer SHA-256 and byte size match canonical release.json.' }
}

if (-not (Test-Path -LiteralPath $zip -PathType Leaf)) { Fail "ZIP archive is missing: $zip" }
else { Pass "ZIP archive present: $(Split-Path -Leaf $zip)" }
if ($failures.Count) { throw "GY release verification failed: $($failures.Count) problem(s)." }
Write-Host "GY release verification passed for $Version." -ForegroundColor Green
