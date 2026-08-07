# Shared transaction-lock helpers for the ZIP installer, Finalizer and rollback.
# The Inno Setup installer uses the same named Win32 mutex directly.

Set-StrictMode -Version Latest

$script:GYInputTransactionMutexName = 'Global\GYInputFinalizePending'

function New-GYInputTransactionMutex {
  return [Threading.Mutex]::new($false, $script:GYInputTransactionMutexName)
}
function Remove-GYInputScheduledTask {
  param([Parameter(Mandatory = $true)][string]$TaskName)
  $schtasks = Join-Path $env:WINDIR 'System32\schtasks.exe'
  $result = Start-Process -FilePath $schtasks -ArgumentList @('/Delete','/TN',$TaskName,'/F') -Wait -PassThru -WindowStyle Hidden
  return $result.ExitCode -eq 0
}

function Wait-GYInputScheduledTask {
  param([Parameter(Mandatory = $true)][string]$TaskName, [int]$Attempts = 10)
  $schtasks = Join-Path $env:WINDIR 'System32\schtasks.exe'
  for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
    $result = Start-Process -FilePath $schtasks -ArgumentList @('/Query','/TN',$TaskName) -Wait -PassThru -WindowStyle Hidden
    if ($result.ExitCode -eq 0) { return $true }
    Start-Sleep -Milliseconds 200
  }
  return $false
}
function Invoke-WithGYInputTransaction {
  param(
    [Parameter(Mandatory = $true)]
    [scriptblock]$Action,
    [int]$TimeoutMilliseconds = 0
  )

  $mutex = New-GYInputTransactionMutex
  $lockTaken = $false
  try {
    $lockTaken = $mutex.WaitOne($TimeoutMilliseconds)
    if (-not $lockTaken) {
      throw 'Another GYInput activation transaction is already running.'
    }
    & $Action
  } finally {
    if ($lockTaken) { try { $mutex.ReleaseMutex() } catch {} }
    $mutex.Dispose()
  }
}

function Assert-GYInputTransactionHeld {
  param(
    [Parameter(Mandatory = $true)]
    [bool]$LockAlreadyHeld
  )

  if (-not $LockAlreadyHeld) {
    throw 'GYInput Finalizer was invoked without its transaction lock.'
  }
}
