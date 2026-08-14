[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$InstallerPath,

  [Parameter(Mandatory = $true)]
  [string]$ExpectedInitialVersion,

  [switch]$KeepCandidateActive,

  # Optional, but required when the machine is not already on
  # ExpectedInitialVersion.  Its immutable EXE and adjacent package manifest
  # are verified before it can establish the acceptance baseline.
  [string]$BaselineInstallerPath
)

# Developer acceptance harness. This is deliberately not packaged for end
# users: it changes the active version in a controlled .old -> .new -> .old
# sequence, verifies every boundary, and can optionally leave .new active.

$ErrorActionPreference = 'Stop'
$programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$installRoot = Join-Path $programFiles 'GYInput'
$statePath = Join-Path $installRoot 'install-state.json'
$reportPath = Join-Path $installRoot 'recovery-report.json'
$validatePath = Join-Path $installRoot 'Validate-GYInput.ps1'
$sourceRepairPath = Join-Path $PSScriptRoot 'Repair-GYInput.ps1'
$sourceRollbackPath = Join-Path $PSScriptRoot 'Rollback-GYInput.ps1'
$timestamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$logPath = Join-Path $env:ProgramData "GYInput\upgrade-rollback-e2e-$timestamp.log"

function Write-TestLog([string]$Message) {
  $line = '[{0}] {1}' -f [DateTime]::UtcNow.ToString('o'), $Message
  Add-Content -LiteralPath $logPath -Value $line -Encoding utf8
  Write-Host $line
}

function Assert-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this acceptance harness from an Administrator PowerShell window.'
  }
}

function Get-ActiveState {
  if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw "Missing active state: $statePath"
  }
  return Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
}

function Assert-ActiveVersion([string]$ExpectedVersion, [string]$Stage) {
  $state = Get-ActiveState
  if ([string]$state.version -ne $ExpectedVersion -or
      [string]$state.hostVersion -ne $ExpectedVersion -or
      [string]$state.coreVersion -ne $ExpectedVersion -or
      [string]$state.activationState -ne 'active' -or
      $state.registryVerified -ne $true) {
    throw "$Stage did not leave the expected verified active state v$ExpectedVersion."
  }
}

function Assert-PendingCandidate([string]$ExpectedVersion) {
  $state = Get-ActiveState
  if ([string]$state.version -ne $ExpectedVersion -or [string]$state.activationState -ne 'pending') {
    throw "Installer did not produce the expected pending state for v$ExpectedVersion."
  }
}

function Assert-RollbackSnapshot([string]$ExpectedVersion) {
  $previousPath = Join-Path $installRoot 'install-state.previous.json'
  if (-not (Test-Path -LiteralPath $previousPath -PathType Leaf)) {
    throw 'Candidate install did not preserve a rollback snapshot.'
  }
  $previous = Get-Content -LiteralPath $previousPath -Raw | ConvertFrom-Json
  if ([string]$previous.version -ne $ExpectedVersion -or
      [string]$previous.hostVersion -ne $ExpectedVersion -or
      [string]$previous.coreVersion -ne $ExpectedVersion -or
      [string]$previous.activationState -ne 'active' -or
      $previous.registryVerified -ne $true -or
      $previous.requiresClientReload -ne $false -or
      -not (Test-Path -LiteralPath ([string]$previous.dll) -PathType Leaf) -or
      -not (Test-Path -LiteralPath ([string]$previous.host) -PathType Leaf) -or
      -not (Test-Path -LiteralPath ([string]$previous.health) -PathType Leaf)) {
    throw "Candidate install wrote an ineligible rollback snapshot for v$ExpectedVersion."
  }
}

function Get-SetupVersion([string]$Path) {
  $match = [regex]::Match((Split-Path -Leaf $Path), '^GYInputSetup-(\d+\.\d+\.\d+)\.exe$')
  if (-not $match.Success) { throw "Installer filename must be GYInputSetup-x.y.z.exe: $Path" }
  return $match.Groups[1].Value
}

function Assert-VerifiedBaselineInstaller([string]$Path, [string]$ExpectedVersion) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing baseline installer: $Path" }
  $actualVersion = Get-SetupVersion $Path
  if ($actualVersion -ne $ExpectedVersion) {
    throw "Baseline installer version $actualVersion does not match expected baseline $ExpectedVersion."
  }
  $releaseRoot = Split-Path -Parent $Path
  $packageManifest = Join-Path (Join-Path $releaseRoot "GYInput-$ExpectedVersion") 'release.json'
  if (-not (Test-Path -LiteralPath $packageManifest -PathType Leaf)) {
    throw "Baseline package manifest is missing beside the installer: $packageManifest"
  }
  $manifest = Get-Content -LiteralPath $packageManifest -Raw | ConvertFrom-Json
  if ([string]$manifest.windows.version -ne $ExpectedVersion -or
      [string]$manifest.windows.setupFile -ne (Split-Path -Leaf $Path) -or
      [string]$manifest.windows.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
      [Int64]$manifest.windows.bytes -le 0) {
    throw 'Baseline package manifest is incomplete or inconsistent.'
  }
  $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
  $actualBytes = (Get-Item -LiteralPath $Path).Length
  if ($actualHash -ne [string]$manifest.windows.sha256 -or $actualBytes -ne [Int64]$manifest.windows.bytes) {
    throw 'Baseline installer hash or byte size does not match its immutable manifest.'
  }
}

function Wait-PendingCandidate([string]$ExpectedVersion, [int]$TimeoutSeconds = 45) {
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  do {
    try {
      $state = Get-ActiveState
      if ([string]$state.version -eq $ExpectedVersion -and [string]$state.activationState -eq 'pending') {
        return
      }
    } catch {}
    Start-Sleep -Milliseconds 250
  } while ([DateTime]::UtcNow -lt $deadline)
  Assert-PendingCandidate $ExpectedVersion
}

function Wait-StagedOrActiveRelease([string]$ExpectedVersion, [int]$TimeoutSeconds = 45) {
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  do {
    try {
      $state = Get-ActiveState
      if ([string]$state.version -eq $ExpectedVersion -and
          [string]$state.activationState -in @('pending', 'active')) {
        return $state
      }
    } catch {}
    Start-Sleep -Milliseconds 250
  } while ([DateTime]::UtcNow -lt $deadline)
  throw "Installer did not stage or activate expected version v$ExpectedVersion within $TimeoutSeconds seconds."
}

function Invoke-InstalledValidation([string]$Stage) {
  if (-not (Test-Path -LiteralPath $validatePath -PathType Leaf)) { throw "Missing validator: $validatePath" }
  Write-TestLog "validate: $Stage"
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validatePath 2>&1 |
    Tee-Object -FilePath $logPath -Append
  if ($LASTEXITCODE -ne 0) { throw "Validation failed at stage: $Stage" }
}

function Install-Release([string]$SetupPath, [string]$ExpectedVersion, [string]$Stage) {
  Write-TestLog "install ${Stage}: v$ExpectedVersion"
  $setupLog = Join-Path $env:ProgramData "GYInput\e2e-setup-$ExpectedVersion-$timestamp.log"
  $setup = Start-Process -FilePath $SetupPath -ArgumentList @(
    '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/LOG="{0}"' -f $setupLog)
  ) -Wait -PassThru
  if ($setup.ExitCode -ne 0) { throw "Installer returned exit code $($setup.ExitCode)." }
  # Inno can hand off to a child Setup process. Wait for the durable pending
  # state rather than treating the first parent process exit as completion.
  return Wait-StagedOrActiveRelease $ExpectedVersion
}

function Install-Candidate([string]$ExpectedVersion, [string]$ExpectedRollbackVersion) {
  $state = Install-Release $InstallerPath $ExpectedVersion 'candidate'
  if ([string]$state.activationState -ne 'pending') {
    throw "Candidate v$ExpectedVersion did not enter the required pending activation state."
  }
  Assert-RollbackSnapshot $ExpectedRollbackVersion
}

function Complete-PendingCandidate([string]$ExpectedVersion) {
  if (-not (Test-Path -LiteralPath $sourceRepairPath -PathType Leaf)) { throw "Missing audited repair script: $sourceRepairPath" }
  Write-TestLog "complete pending candidate: v$ExpectedVersion"
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sourceRepairPath -Elevated 2>&1 |
    Tee-Object -FilePath $logPath -Append
  if ($LASTEXITCODE -ne 0) { throw "Pending activation repair failed for v$ExpectedVersion." }
  Assert-ActiveVersion $ExpectedVersion 'Pending activation repair'
  Invoke-InstalledValidation "candidate v$ExpectedVersion"
}

function Invoke-VerifiedRollback([string]$ExpectedVersion) {
  if (-not (Test-Path -LiteralPath $sourceRollbackPath -PathType Leaf)) { throw "Missing audited rollback script: $sourceRollbackPath" }
  Write-TestLog "rollback to: v$ExpectedVersion"
  # The acceptance harness already runs elevated. Passing this marker keeps an
  # installed pre-fix rollback script from opening a nested UAC process and
  # blocking the state-machine test at the .new -> .old boundary.
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sourceRollbackPath -Elevated 2>&1 |
    Tee-Object -FilePath $logPath -Append
  if ($LASTEXITCODE -ne 0) { throw "Rollback returned exit code $LASTEXITCODE." }
  Assert-ActiveVersion $ExpectedVersion 'Rollback'
  Invoke-InstalledValidation "rollback v$ExpectedVersion"
  if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw 'Rollback did not produce recovery-report.json.' }
  $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
  if ([string]$report.action -ne 'rollback' -or [string]$report.status -ne 'succeeded' -or
      [string]$report.toVersion -ne $ExpectedVersion) {
    throw 'Rollback report does not prove a successful recovery transaction.'
  }
}

function Ensure-AcceptanceBaseline([string]$ExpectedVersion) {
  $state = Get-ActiveState
  if ([string]$state.version -eq $ExpectedVersion -and
      [string]$state.activationState -eq 'active' -and
      $state.registryVerified -eq $true) {
    return
  }
  if ([string]::IsNullOrWhiteSpace($BaselineInstallerPath)) {
    throw "Current verified version is v$($state.version), not required baseline v$ExpectedVersion. Supply -BaselineInstallerPath; the harness will not substitute another rollback target."
  }
  Assert-VerifiedBaselineInstaller $BaselineInstallerPath $ExpectedVersion
  Write-TestLog "establish verified baseline: v$ExpectedVersion"
  $baselineState = Install-Release $BaselineInstallerPath $ExpectedVersion 'baseline'
  if ([string]$baselineState.activationState -eq 'pending') {
    Complete-PendingCandidate $ExpectedVersion
  }
  Assert-ActiveVersion $ExpectedVersion 'Established baseline'
  Invoke-InstalledValidation "established baseline v$ExpectedVersion"
}

Assert-Administrator
if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) { throw "Missing candidate installer: $InstallerPath" }
  $candidateVersion = Get-SetupVersion $InstallerPath

try {
  Write-TestLog "START: expected baseline v$ExpectedInitialVersion; candidate v$candidateVersion"
  $preflightState = Get-ActiveState
  if ([string]$preflightState.version -eq $candidateVersion -and
      [string]$preflightState.activationState -eq 'pending') {
    # A previously interrupted acceptance attempt is still safe to resume:
    # finish its staged activation, prove rollback, then start from baseline.
    Write-TestLog "recover interrupted pending candidate: v$candidateVersion"
    Complete-PendingCandidate $candidateVersion
    Invoke-VerifiedRollback $ExpectedInitialVersion
  }
  Ensure-AcceptanceBaseline $ExpectedInitialVersion
  Assert-ActiveVersion $ExpectedInitialVersion 'Baseline'
  Invoke-InstalledValidation "baseline v$ExpectedInitialVersion"

  Install-Candidate $candidateVersion $ExpectedInitialVersion
  Complete-PendingCandidate $candidateVersion
  Invoke-VerifiedRollback $ExpectedInitialVersion

  if ($KeepCandidateActive) {
    Install-Candidate $candidateVersion $ExpectedInitialVersion
    Complete-PendingCandidate $candidateVersion
  }

  Write-TestLog 'RESULT: PASS'
  Write-Host "GY upgrade/rollback acceptance passed. Log: $logPath" -ForegroundColor Green
  exit 0
} catch {
  Write-TestLog ('RESULT: FAIL: ' + $_.Exception.Message)
  Write-Error "GY upgrade/rollback acceptance failed. Active state was not forcibly changed after the failure. Log: $logPath`n$($_.Exception.Message)"
  exit 1
}
