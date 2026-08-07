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
if (-not (Test-Path -LiteralPath $pendingPath -PathType Leaf)) { exit 0 }
$commonDataRoot = Join-Path $env:ProgramData 'GYInput'
$finalizerPath = Join-Path $commonDataRoot 'Finalize-GYClientReload.ps1'
$taskName = 'GYInput\ActivatePending'
$taskNameLogon = 'GYInput\ActivatePendingLogon'

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
  Register-GYInputActivationTasksCore
} else {
  Invoke-WithGYInputTransaction {
    Register-GYInputActivationTasksCore
  }
}
