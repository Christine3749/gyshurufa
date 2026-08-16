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
  if ($version -in @('0.10.96', '0.10.97', '0.12.6', '0.12.7', '0.12.8')) { throw "Withdrawn GY version $version can never be packaged, signed, or published." }
  return $version
}

function Get-GYReleaseApprovalPath {
  param(
    [Parameter(Mandatory)][string]$Version,
    [string]$ManifestPath = (Get-GYReleaseManifestPath)
  )
  $releaseRoot = Split-Path -Parent $ManifestPath
  return Join-Path (Join-Path $releaseRoot 'approvals') "$Version.json"
}

function Assert-GYReleaseApproval {
  param(
    [Parameter(Mandatory)]$Manifest,
    [Parameter(Mandatory)][string]$Version,
    [string]$ApprovalPath = (Get-GYReleaseApprovalPath -Version $Version)
  )

  if (-not (Test-Path -LiteralPath $ApprovalPath -PathType Leaf)) {
    throw "Release approval is missing: $ApprovalPath. A draft may be built and tested, but packaging, signing, finalization, and publishing require an explicit recorded approval."
  }
  try {
    $approval = Get-Content -LiteralPath $ApprovalPath -Raw | ConvertFrom-Json
  } catch {
    throw "Release approval cannot be parsed: $ApprovalPath. $($_.Exception.Message)"
  }
  foreach ($property in 'schemaVersion', 'releaseId', 'version', 'channel', 'state', 'approvedBy', 'approvedAtUtc', 'gates') {
    if (-not $approval.PSObject.Properties.Name.Contains($property)) { throw "Release approval field is missing: $property" }
  }
  if ([int]$approval.schemaVersion -ne 1) { throw "Unsupported release approval schema: $($approval.schemaVersion). Expected 1." }
  if ([string]$approval.releaseId -ne [string]$Manifest.releaseId) { throw 'Release approval does not match the canonical releaseId.' }
  if ([string]$approval.version -ne $Version) { throw 'Release approval version does not match the canonical Windows version.' }
  if ([string]$approval.channel -ne [string]$Manifest.channel) { throw 'Release approval channel does not match the canonical release channel.' }
  if ([string]$approval.state -ne 'approved') { throw 'Release approval state must be approved.' }
  if ([string]::IsNullOrWhiteSpace([string]$approval.approvedBy)) { throw 'Release approval must record who approved it.' }
  [DateTime]$approvedAt = [DateTime]::MinValue
  if (-not [DateTime]::TryParse([string]$approval.approvedAtUtc, [Globalization.CultureInfo]::InvariantCulture,
                                 [Globalization.DateTimeStyles]::RoundtripKind, [ref]$approvedAt)) {
    throw 'Release approval must record an ISO-8601 approval time.'
  }
  foreach ($gate in 'sourceAudit', 'rollback', 'realApplications', 'privacyBoundary') {
    if (-not $approval.gates.PSObject.Properties.Name.Contains($gate) -or [string]$approval.gates.$gate -ne 'passed') {
      throw "Release approval gate '$gate' is not recorded as passed."
    }
  }
  return $approval
}

function Assert-GYCandidateDistributionApproval {
  param(
    [Parameter(Mandatory)]$Manifest,
    [Parameter(Mandatory)][string]$Version,
    [string]$ApprovalPath = (Get-GYReleaseApprovalPath -Version $Version)
  )

  if ([string]$Manifest.channel -ne 'candidate' -or [string]$Manifest.windows.state -ne 'candidate') {
    throw 'Target-test distribution approval is valid only for a finalized Windows candidate.'
  }
  if (-not (Test-Path -LiteralPath $ApprovalPath -PathType Leaf)) {
    throw "Candidate distribution approval is missing: $ApprovalPath."
  }
  try {
    $approval = Get-Content -LiteralPath $ApprovalPath -Raw | ConvertFrom-Json
  } catch {
    throw "Candidate distribution approval cannot be parsed: $ApprovalPath. $($_.Exception.Message)"
  }
  foreach ($property in 'schemaVersion', 'releaseId', 'version', 'channel', 'state', 'approvalKind',
                        'approvedBy', 'approvedAtUtc', 'audience', 'gates') {
    if (-not $approval.PSObject.Properties.Name.Contains($property)) {
      throw "Candidate distribution approval field is missing: $property"
    }
  }
  if ([int]$approval.schemaVersion -ne 1 -or [string]$approval.approvalKind -ne 'target-test-distribution') {
    throw 'Candidate distribution approval must be schema 1 and target-test-distribution.'
  }
  if ([string]$approval.releaseId -ne [string]$Manifest.releaseId -or
      [string]$approval.version -ne $Version -or
      [string]$approval.channel -ne 'candidate' -or
      [string]$approval.state -ne 'approved') {
    throw 'Candidate distribution approval identity does not match the canonical candidate.'
  }
  if ([string]::IsNullOrWhiteSpace([string]$approval.approvedBy) -or
      [string]::IsNullOrWhiteSpace([string]$approval.audience)) {
    throw 'Candidate distribution approval must name the approver and target audience.'
  }
  [DateTime]$approvedAt = [DateTime]::MinValue
  if (-not [DateTime]::TryParse([string]$approval.approvedAtUtc, [Globalization.CultureInfo]::InvariantCulture,
                                 [Globalization.DateTimeStyles]::RoundtripKind, [ref]$approvedAt)) {
    throw 'Candidate distribution approval must record an ISO-8601 approval time.'
  }
  foreach ($gate in 'sourceAudit', 'packageVerification', 'privacyBoundary') {
    if (-not $approval.gates.PSObject.Properties.Name.Contains($gate) -or [string]$approval.gates.$gate -ne 'passed') {
      throw "Candidate distribution approval gate '$gate' is not recorded as passed."
    }
  }
  if (-not $approval.gates.PSObject.Properties.Name.Contains('targetAcceptance') -or
      [string]$approval.gates.targetAcceptance -notin @('pending-on-target', 'passed')) {
    throw 'Candidate distribution approval must explicitly record targetAcceptance as pending-on-target or passed.'
  }
  if (-not $approval.PSObject.Properties.Name.Contains('unsignedCandidateAcknowledged') -or
      $approval.unsignedCandidateAcknowledged -ne $true) {
    throw 'Candidate distribution approval must acknowledge the unsigned Windows candidate.'
  }
  return $approval
}

Export-ModuleMember -Function Get-GYReleaseManifestPath, Get-GYReleaseManifest, Assert-GYReleaseVersion, Get-GYReleaseApprovalPath, Assert-GYReleaseApproval, Assert-GYCandidateDistributionApproval
