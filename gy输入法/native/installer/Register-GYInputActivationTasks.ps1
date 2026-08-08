param([switch]$LockAlreadyHeld)

# Register the startup and logon activation tasks from a native PowerShell
# process.  Inno Setup is a 32-bit host on x64 Windows; delegating the actual
# schtasks calls here keeps the installer and ZIP paths on the same code path.

$ErrorActionPreference = 'Stop'
$transactionHelper = Join-Path $PSScriptRoot 'GYInputTransaction.ps1'
if (-not (Test-Path -LiteralPath $transactionHelper -PathType Leaf)) {
  throw 'GY Input transaction helper is missing.'
}
. $transactionHelper

$programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$installRoot = Join-Path $programFiles 'GYInput'
$pendingPath = Join-Path $installRoot 'pending-activation.json'
$commonDataRoot = Join-Path $env:ProgramData 'GYInput'
$finalizerPath = Join-Path $commonDataRoot 'Finalize-GYClientReload.ps1'
$taskName = 'GYInput\ActivatePending'
$taskNameLogon = 'GYInput\ActivatePendingLogon'

function Remove-StaleTransientHelpers {
  # The EXE and ZIP installers may stage these files before knowing whether a
  # core reload is needed. If this is a normal/first install there is no task
  # to run, so remove the staged copies immediately. The script itself runs
  # from the package or Program Files, never from this common-data list.
  if (Test-Path -LiteralPath $pendingPath -PathType Leaf) { return }
  Remove-GYInputScheduledTask $taskName | Out-Null
  Remove-GYInputScheduledTask $taskNameLogon | Out-Null
  foreach ($helper in @(
    'Finalize-GYClientReload.ps1',
    'Prune-GYOldVersions.ps1',
    'GYInputTransaction.ps1',
    'Register-GYInputActivationTasks.ps1'
  )) {
    Remove-Item -LiteralPath (Join-Path $commonDataRoot $helper) -Force -ErrorAction SilentlyContinue
  }
}

function Register-GYInputActivationTasksCore {
  if (-not (Test-Path -LiteralPath $finalizerPath -PathType Leaf)) {
    throw "GY Input Finalizer is missing: $finalizerPath"
  }

  $schtasks = Join-Path $env:WINDIR 'System32\schtasks.exe'
  $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

  function Register-One([string]$TaskName, [string]$Schedule) {
    $taskArgs = '/Create /TN "' + $TaskName +
                '" /SC ' + $Schedule + ' /RU SYSTEM /RL HIGHEST /F /TR "' +
                $powershell + ' -NoProfile -ExecutionPolicy Bypass -File ' +
                $finalizerPath + '"'
    $result = Start-Process -FilePath $schtasks -ArgumentList $taskArgs -Wait -PassThru -WindowStyle Hidden
    if ($result.ExitCode -ne 0) {
      throw "Unable to schedule GY activation task '$TaskName' (schtasks exit code: $($result.ExitCode))."
    }
    if (-not (Wait-GYInputScheduledTask $TaskName)) {
      throw "Scheduled activation task '$TaskName' did not persist after creation."
    }
  }

  try {
    Register-One $taskName 'ONSTART'
    Register-One $taskNameLogon 'ONLOGON'
    if (-not (Wait-GYInputScheduledTask $taskName) -or
        -not (Wait-GYInputScheduledTask $taskNameLogon)) {
      throw 'One or more GY activation tasks failed the final readback.'
    }
  } catch {
    Remove-GYInputScheduledTask $taskName | Out-Null
    Remove-GYInputScheduledTask $taskNameLogon | Out-Null
    throw
  }
}

if ($LockAlreadyHeld) {
  if (Test-Path -LiteralPath $pendingPath -PathType Leaf) {
    Register-GYInputActivationTasksCore
  } else {
    Remove-StaleTransientHelpers
  }
} else {
  Invoke-WithGYInputTransaction {
    if (Test-Path -LiteralPath $pendingPath -PathType Leaf) {
      Register-GYInputActivationTasksCore
    } else {
      Remove-StaleTransientHelpers
    }
  }
}
