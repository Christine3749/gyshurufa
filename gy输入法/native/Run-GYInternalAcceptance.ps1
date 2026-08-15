[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$PackageRoot,
  [switch]$RunRealWindow,
  [switch]$AllowLiveMachineActivation
)

# One-machine acceptance harness. It is intentionally unable to publish or
# retain its candidate. It accepts only a prepared internal root, demands an
# active 0.10.95 baseline, and always attempts verified rollback in finally.
# Live activation must be explicitly opted in for each run; normal source and
# build verification must never alter the user's installed input method.
$ErrorActionPreference = 'Stop'
if (-not $AllowLiveMachineActivation) {
  throw 'Refusing live input-method activation. Run non-live checks by default; this harness requires -AllowLiveMachineActivation.'
}
$PackageRoot = [IO.Path]::GetFullPath($PackageRoot)
$marker = Join-Path $PackageRoot 'INTERNAL-ACCEPTANCE-NOT-FOR-DISTRIBUTION.txt'
$recordPath = Join-Path $PackageRoot 'internal-acceptance.json'
$install = Join-Path $PackageRoot 'Install-GYInput.ps1'
$rollback = Join-Path $PackageRoot 'Rollback-GYInput.ps1'
$realWindow = Join-Path $PackageRoot 'tools\GyEnRealAppRegression.exe'
$expectedBaseline = '0.10.95'
$expectedCandidate = (Get-Content -LiteralPath (Join-Path $PackageRoot 'VERSION') -Raw).Trim()
if ($expectedCandidate -notmatch '^\d+\.\d+\.\d+$') {
  throw "Refusing: internal acceptance package has an invalid VERSION: $expectedCandidate"
}

function Get-GyInstallRoot {
  $programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
  return Join-Path $programFiles 'GYInput'
}
function Get-ActiveGyVersion {
  try { return [string](Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\GYInput' -Name HostVersion -ErrorAction Stop) }
  catch { return '' }
}
function Get-ActiveGyState {
  $path = Join-Path (Get-GyInstallRoot) 'install-state.json'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Active GY state is missing: $path" }
  return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}
function Assert-ActiveVersion([string]$Expected, [string]$Stage) {
  $state = Get-ActiveGyState
  if ((Get-ActiveGyVersion) -ne $Expected -or [string]$state.version -ne $Expected -or
      [string]$state.coreVersion -ne $Expected -or [string]$state.activationState -ne 'active' -or
      $state.registryVerified -ne $true) {
    throw "$Stage did not leave verified active GY $Expected."
  }
}
function Invoke-PackageScript([string]$Path, [string]$Label, [string[]]$Arguments = @()) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label script is missing: $Path" }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$Label returned exit code $LASTEXITCODE." }
}
function Test-CandidatePending {
  $pendingPath = Join-Path (Get-GyInstallRoot) 'pending-activation.json'
  if (-not (Test-Path -LiteralPath $pendingPath -PathType Leaf)) { return $false }
  try {
    $pending = Get-Content -LiteralPath $pendingPath -Raw | ConvertFrom-Json
    return [string]$pending.version -eq $expectedCandidate
  } catch {
    throw 'Pending activation record cannot be read; refusing to guess about cleanup.'
  }
}
function Assert-BaselineSnapshot {
  $previousPath = Join-Path (Get-GyInstallRoot) 'install-state.previous.json'
  if (-not (Test-Path -LiteralPath $previousPath -PathType Leaf)) { throw 'Candidate install did not create a rollback snapshot.' }
  $previous = Get-Content -LiteralPath $previousPath -Raw | ConvertFrom-Json
  if ([string]$previous.version -ne $expectedBaseline -or
      [string]$previous.host -notmatch [regex]::Escape("versions\$expectedBaseline\GyImeHost-$expectedBaseline.exe") -or
      [string]$previous.dll -notmatch [regex]::Escape("tsf-$expectedBaseline\GyIme.dll")) {
    throw 'Candidate install did not preserve the exact 0.10.95 rollback target.'
  }
}
function Assert-CandidatePayloadActivated {
  $installRoot = Get-GyInstallRoot
  $checks = @(
    @{ Name = 'TSF DLL'; Source = (Join-Path $PackageRoot "payload\GyIme-$expectedCandidate.dll"); Destination = (Join-Path $installRoot "tsf-$expectedCandidate\GyIme.dll") },
    @{ Name = 'Host'; Source = (Join-Path $PackageRoot "payload\GyImeHost-$expectedCandidate.exe"); Destination = (Join-Path $installRoot "versions\$expectedCandidate\GyImeHost-$expectedCandidate.exe") },
    @{ Name = 'Health check'; Source = (Join-Path $PackageRoot "payload\GyImeHealth-$expectedCandidate.exe"); Destination = (Join-Path $installRoot "versions\$expectedCandidate\GyImeHealth-$expectedCandidate.exe") }
  )
  foreach ($check in $checks) {
    if (-not (Test-Path -LiteralPath $check.Source -PathType Leaf) -or
        -not (Test-Path -LiteralPath $check.Destination -PathType Leaf)) {
      throw "Candidate $($check.Name) payload or installed target is missing."
    }
    $sourceHash = (Get-FileHash -LiteralPath $check.Source -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $check.Destination -Algorithm SHA256).Hash
    if ($sourceHash -ne $destinationHash) {
      throw "Candidate $($check.Name) hash does not match this acceptance build; refusing to test a stale $expectedCandidate file."
    }
  }
}
function Get-InputModeSnapshot {
  $registryPath = 'HKCU:\Software\GYInput'
  $registry = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
  $settingsPath = Join-Path $env:LOCALAPPDATA 'GYInput\settings.ini'
  $settings = if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
    Get-Content -LiteralPath $settingsPath -Raw
  } else { '' }
  $readIni = {
    param([string]$Name)
    $match = [regex]::Match($settings, ('(?m)^' + [regex]::Escape($Name) + '=(\d+)\s*$'))
    if ($match.Success) { return [int]$match.Groups[1].Value }
    return $null
  }
  return [pscustomobject]@{
    RegistryMode = if ($null -ne $registry -and $null -ne $registry.InputMode) { [int]$registry.InputMode } else { $null }
    RegistryLastChineseMode = if ($null -ne $registry -and $null -ne $registry.LastChineseMode) { [int]$registry.LastChineseMode } else { $null }
    SettingsPath = $settingsPath
    SettingsExists = Test-Path -LiteralPath $settingsPath -PathType Leaf
    IniMode = & $readIni 'Mode'
    IniLastChineseMode = & $readIni 'LastChineseMode'
  }
}
function Test-InputModeSnapshot([object]$Expected) {
  $actual = Get-InputModeSnapshot
  return $actual.RegistryMode -eq $Expected.RegistryMode -and
         $actual.RegistryLastChineseMode -eq $Expected.RegistryLastChineseMode -and
         $actual.SettingsExists -eq $Expected.SettingsExists -and
         $actual.IniMode -eq $Expected.IniMode -and
         $actual.IniLastChineseMode -eq $Expected.IniLastChineseMode
}
function Restore-InputModeSnapshot([object]$Expected) {
  $registryPath = 'HKCU:\Software\GYInput'
  foreach ($entry in @(
    @{ Name = 'InputMode'; Value = $Expected.RegistryMode },
    @{ Name = 'LastChineseMode'; Value = $Expected.RegistryLastChineseMode }
  )) {
    if ($null -eq $entry.Value) {
      Remove-ItemProperty -LiteralPath $registryPath -Name $entry.Name -ErrorAction SilentlyContinue
    } else {
      New-Item -Path $registryPath -Force | Out-Null
      New-ItemProperty -LiteralPath $registryPath -Name $entry.Name -Value ([int]$entry.Value) -PropertyType DWord -Force | Out-Null
    }
  }
  if (-not $Expected.SettingsExists) { return }
  $settings = if (Test-Path -LiteralPath $Expected.SettingsPath -PathType Leaf) {
    Get-Content -LiteralPath $Expected.SettingsPath -Raw
  } else { "[Input]`r`n" }
  foreach ($entry in @(
    @{ Name = 'Mode'; Value = $Expected.IniMode },
    @{ Name = 'LastChineseMode'; Value = $Expected.IniLastChineseMode }
  )) {
    if ($null -ne $entry.Value) {
      $pattern = '(?m)^' + [regex]::Escape($entry.Name) + '=\d+\s*$'
      $line = $entry.Name + '=' + [int]$entry.Value
      $settings = if ([regex]::IsMatch($settings, $pattern)) {
        [regex]::Replace($settings, $pattern, $line)
      } else {
        $settings.TrimEnd("`r", "`n") + "`r`n" + $line + "`r`n"
      }
    }
  }
  [IO.File]::WriteAllText($Expected.SettingsPath, $settings, [Text.UTF8Encoding]::new($false))
}
function Assert-InputModeUnchanged([object]$Expected, [string]$Stage) {
  if (-not (Test-InputModeSnapshot $Expected)) {
    $actual = Get-InputModeSnapshot | ConvertTo-Json -Compress
    throw "$Stage changed the user's InputMode state: $actual"
  }
}

if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or -not (Test-Path -LiteralPath $recordPath -PathType Leaf)) {
  throw 'Refusing: this is not a marked internal acceptance root.'
}
$record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
if ($record.purpose -ne 'internal-upgrade-rollback-acceptance-only' -or $record.publicReleaseArtifact -ne $false -or
    $record.version -ne $expectedCandidate -or $record.releaseState -ne 'draft') {
  throw "Refusing: internal acceptance record is incomplete or is not an unpublished $expectedCandidate draft."
}
Assert-ActiveVersion $expectedBaseline 'Preflight'
$inputModeBefore = Get-InputModeSnapshot

$log = Join-Path $PackageRoot ('acceptance-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '.log')
function Write-AcceptanceLog([string]$Text) {
  $line = '[{0}] {1}' -f [DateTime]::UtcNow.ToString('o'), $Text
  Add-Content -LiteralPath $log -Value $line -Encoding utf8
  Write-Host $line
}

$candidateWasActivated = $false
$candidateWasAttempted = $false
$bodyFailure = $null
try {
  Write-AcceptanceLog "START: internal 0.10.95 -> $expectedCandidate acceptance rehearsal."
  Write-AcceptanceLog ('INPUT-MODE-BEFORE: ' + ($inputModeBefore | ConvertTo-Json -Compress))
  $candidateWasAttempted = $true
  Invoke-PackageScript $install 'Internal candidate install'
  Assert-ActiveVersion $expectedCandidate 'Candidate activation'
  Assert-BaselineSnapshot
  Assert-CandidatePayloadActivated
  Assert-InputModeUnchanged $inputModeBefore 'Candidate activation'
  $candidateWasActivated = $true
  Write-AcceptanceLog 'PASS: candidate registry/state activation and input mode are verified.'

  $validator = Join-Path (Get-GyInstallRoot) 'Validate-GYInput.ps1'
  Invoke-PackageScript $validator 'Candidate validation'
  Assert-CandidatePayloadActivated
  Assert-InputModeUnchanged $inputModeBefore 'Candidate validation'
  Write-AcceptanceLog 'PASS: candidate installed validation and input mode are verified.'

  if ($RunRealWindow) {
    if (-not (Test-Path -LiteralPath $realWindow -PathType Leaf)) { throw "Real-window regression binary is missing: $realWindow" }
    Write-AcceptanceLog 'RUN: isolated real RichEdit/password TSF regression.'
    $realOutput = $log + '.real-window.out.txt'
    $realError = $log + '.real-window.err.txt'
    $real = Start-Process -FilePath $realWindow -WorkingDirectory (Split-Path -Parent $realWindow) -Wait -PassThru `
      -RedirectStandardOutput $realOutput -RedirectStandardError $realError
    foreach ($path in @($realOutput, $realError)) {
      if (Test-Path -LiteralPath $path -PathType Leaf) {
        Get-Content -LiteralPath $path | ForEach-Object { Write-AcceptanceLog ('REAL-WINDOW: ' + $_) }
      }
    }
    if ($real.ExitCode -ne 0) { throw "Real-window regression returned exit code $($real.ExitCode)." }
    Write-AcceptanceLog 'PASS: real RichEdit/password TSF regression.'
  }
} catch {
  $bodyFailure = $_
  Write-AcceptanceLog ('FAIL: ' + $_.Exception.Message)
} finally {
  $current = Get-ActiveGyVersion
  if ($current -eq $expectedCandidate) {
    try {
      Write-AcceptanceLog 'ROLLBACK: restoring verified 0.10.95 baseline.'
      Invoke-PackageScript $rollback 'Internal candidate rollback'
      Assert-ActiveVersion $expectedBaseline 'Rollback'
      $validator = Join-Path (Get-GyInstallRoot) 'Validate-GYInput.ps1'
      Invoke-PackageScript $validator 'Baseline validation after rollback'
      Write-AcceptanceLog 'PASS: verified 0.10.95 baseline restored.'
    } catch {
      Write-AcceptanceLog ('ROLLBACK-FAIL: ' + $_.Exception.Message)
      throw
    }
  } elseif ($candidateWasAttempted -and $current -eq $expectedBaseline -and (Test-CandidatePending)) {
    try {
      Write-AcceptanceLog 'CLEANUP: candidate stayed pending; canceling it and restoring verified 0.10.95 baseline.'
      Invoke-PackageScript $install 'Pending candidate rollback cleanup' @('-Rollback')
      Assert-ActiveVersion $expectedBaseline 'Pending candidate rollback cleanup'
      Write-AcceptanceLog 'PASS: pending candidate was canceled and verified 0.10.95 baseline remains active.'
    } catch {
      # Install-GYInput accepts -Rollback; invoke it directly rather than
      # assuming a pending candidate is harmless when the live DLL stayed old.
      Write-AcceptanceLog ('PENDING-CLEANUP-FAIL: ' + $_.Exception.Message)
      throw
    }
  } elseif ($current -ne $expectedBaseline) {
    throw "Unexpected active version during cleanup: $current. Automatic rollback was not attempted against an unknown state."
  }
  if (-not (Test-InputModeSnapshot $inputModeBefore)) {
    Write-AcceptanceLog ('INPUT-MODE-RESTORE: restoring preflight state from ' + ((Get-InputModeSnapshot) | ConvertTo-Json -Compress))
    Restore-InputModeSnapshot $inputModeBefore
  }
  Assert-InputModeUnchanged $inputModeBefore 'Final cleanup'
  Write-AcceptanceLog 'PASS: original InputMode state is preserved.'
}
if ($bodyFailure) { throw $bodyFailure }
Write-AcceptanceLog "RESULT: PASS; $expectedCandidate was not retained."
Write-Host "Internal acceptance passed. 0.10.95 remains active. Log: $log" -ForegroundColor Green
