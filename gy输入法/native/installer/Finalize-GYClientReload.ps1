# Finalize-GYClientReload.ps1
param(
  [switch]$LockAlreadyHeld,
  [switch]$StartupTrigger
)
#
# Runs once at Windows startup after a core DLL upgrade.  The installer stages
# the new version but deliberately leaves the old TSF registration active until
# this script runs, so no application can observe a mixed registration state.

$ErrorActionPreference = 'Stop'
$transactionHelper = Join-Path $PSScriptRoot 'GYInputTransaction.ps1'
if (-not (Test-Path -LiteralPath $transactionHelper -PathType Leaf)) { throw 'GYInput transaction helper is missing.' }
. $transactionHelper

$programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$installRoot = Join-Path $programFiles 'GYInput'
$commonDataRoot = Join-Path $env:ProgramData 'GYInput'
$pendingPath = Join-Path $installRoot 'pending-activation.json'
$taskName = 'GYInput\ActivatePending'
$legacyLogonTaskName = 'GYInput\ActivatePendingLogon'
$regsvr32 = Join-Path $env:WINDIR 'System32\regsvr32.exe'
$prunePath = Join-Path $commonDataRoot 'Prune-GYOldVersions.ps1'
$legacyMigrationPath = Join-Path $installRoot 'Migrate-GYLegacyInstallEntries.ps1'
$errorPath = Join-Path $installRoot 'pending-activation.error.log'
$statePath = Join-Path $installRoot 'install-state.json'

$pending = $null
$previousDll = ''
$previousHost = ''
$previousHealth = ''
$previousVersion = ''
$registrationChanged = $false

$mutex = $null
$lockTaken = $false
if (-not $LockAlreadyHeld) {
  $mutex = New-GYInputTransactionMutex
  $lockTaken = $mutex.WaitOne(0)
  if (-not $lockTaken) { $mutex.Dispose(); exit 0 }
}

function Remove-PendingTask {
  try {
    Remove-GYInputScheduledTask $taskName | Out-Null
    Remove-GYInputScheduledTask $legacyLogonTaskName | Out-Null
  } catch {}
}

function Start-TransientHelperCleanup {
  # A running PowerShell process cannot reliably delete the script that
  # launched it. Start a short-lived child that first waits for this Finalizer
  # to exit, then takes the same transaction mutex before removing only the
  # known staged helpers. If a new installer owns the mutex or has created a
  # fresh pending transaction, it exits without touching the new helpers.
  $cleanupPaths = @(
    (Join-Path $commonDataRoot 'Finalize-GYClientReload.ps1'),
    (Join-Path $commonDataRoot 'Prune-GYOldVersions.ps1'),
    (Join-Path $commonDataRoot 'GYInputTransaction.ps1'),
    (Join-Path $commonDataRoot 'Register-GYInputActivationTasks.ps1')
  )
  $quotedPaths = ($cleanupPaths | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ','
  $quotedPending = "'" + $pendingPath.Replace("'", "''") + "'"
  $cleanup = @"
`$parentProcessId = $PID
`$pendingActivationPath = $quotedPending
`$helperPaths = @($quotedPaths)
try { Wait-Process -Id `$parentProcessId -ErrorAction SilentlyContinue } catch {}
`$mutex = [Threading.Mutex]::new(`$false, 'Global\GYInputFinalizePending')
`$lockTaken = `$false
try {
  `$lockTaken = `$mutex.WaitOne(0)
  if (-not `$lockTaken -or (Test-Path -LiteralPath `$pendingActivationPath -PathType Leaf)) { exit 0 }
  foreach (`$helperPath in `$helperPaths) {
    if (Test-Path -LiteralPath `$helperPath -PathType Leaf) {
      Remove-Item -LiteralPath `$helperPath -Force -ErrorAction SilentlyContinue
    }
  }
} finally {
  if (`$lockTaken) { try { `$mutex.ReleaseMutex() } catch {} }
  `$mutex.Dispose()
}
"@
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cleanup))
  $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  Start-Process -FilePath $powershell -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded
  ) -WindowStyle Hidden | Out-Null
}

function Write-Failure([string]$Message) {
  try {
    $stamp = [DateTime]::UtcNow.ToString('o')
    "$stamp $Message" | Set-Content -LiteralPath $errorPath -Encoding utf8
  } catch {}
}

function Test-ManagedPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  try {
    $root = [IO.Path]::GetFullPath($installRoot).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath($Path)
    return $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)
  } catch {
    return $false
  }
}

function Test-SamePath([string]$Left, [string]$Right) {
  return [string]::Equals($Left, $Right, [StringComparison]::OrdinalIgnoreCase)
}

function Read-RegisteredString([string]$SubKey, [string]$ValueName) {
  $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($SubKey)
  if (-not $key) { return '' }
  try { return [string]$key.GetValue($ValueName) } finally { $key.Dispose() }
}

function Assert-RegisteredGyState([string]$Dll, [string]$HostPath, [string]$Version, [string]$Context) {
  $registeredDll = Read-RegisteredString 'Software\Classes\CLSID\{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}\InprocServer32' ''
  $registeredHost = Read-RegisteredString 'Software\GYInput' 'HostPath'
  $registeredVersion = Read-RegisteredString 'Software\GYInput' 'HostVersion'
  if (-not (Test-SamePath $registeredDll $Dll) -or
      -not (Test-SamePath $registeredHost $HostPath) -or
      $registeredVersion -ne $Version) {
    throw "$Context registry readback does not match the expected DLL, Host, and version."
  }
}

function Assert-NoRegisteredGyState([string]$Context) {
  $registeredDll = Read-RegisteredString 'Software\Classes\CLSID\{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}\InprocServer32' ''
  $registeredHost = Read-RegisteredString 'Software\GYInput' 'HostPath'
  $registeredVersion = Read-RegisteredString 'Software\GYInput' 'HostVersion'
  if ($registeredDll -or $registeredHost -or $registeredVersion) {
    throw "$Context found an unexpected GY registration; refusing to overwrite it without a rollback snapshot."
  }
}

function Get-CurrentBootId {
  $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
    'SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters')
  if (-not $key) { throw 'Windows BootId is unavailable; pending activation remains staged.' }
  try {
    $value = $key.GetValue('BootId', $null)
    if ($null -eq $value) { throw 'Windows BootId is unavailable; pending activation remains staged.' }
    return [uint32]$value
  } finally { $key.Dispose() }
}

function Assert-OfflineHealthy([string]$HealthPath, [string]$Context) {
  $result = Start-Process -FilePath $HealthPath -WorkingDirectory (Split-Path -Parent $HealthPath) -Wait -PassThru
  if ($result.ExitCode -ne 0) { throw "$Context health check failed (exit code: $($result.ExitCode))." }
}

function Write-VerifiedActiveState([string]$Version, [string]$Dll, [string]$HostPath,
                                   [string]$HealthPath, [string]$PreviousVersion) {
  $retainedVersion = $null
  if ($PreviousVersion -match '^\d+\.\d+\.\d+$') { $retainedVersion = $PreviousVersion }
  $state = [ordered]@{
    schemaVersion = 2
    version = $Version
    hostVersion = $Version
    coreVersion = $Version
    installedAtUtc = [DateTime]::UtcNow.ToString('o')
    dll = $Dll
    host = $HostPath
    health = $HealthPath
    updateModel = 'versioned-tsf-host'
    activationState = 'active'
    registryVerified = $true
    requiresClientReload = $false
    previousCoreVersion = $retainedVersion
  }
  $temporary = Join-Path $installRoot ('.install-state.json.' + [Guid]::NewGuid().ToString('N') + '.tmp')
  try {
    [IO.File]::WriteAllText($temporary, ($state | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $statePath -Force
  } finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
  }
}

function Invoke-LegacyInstallMigration([string]$Version) {
  # Add/Remove Programs cleanup is post-activation housekeeping.  It must never
  # roll back a verified TSF/Host switch if a corrupted legacy registry entry
  # cannot be removed on this machine.
  if (-not (Test-Path -LiteralPath $legacyMigrationPath -PathType Leaf)) { return }
  try {
    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $result = Start-Process -FilePath $powershell -ArgumentList @(
      '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $legacyMigrationPath,
      '-InstallRoot', $installRoot, '-CurrentVersion', $Version
    ) -Wait -PassThru -WindowStyle Hidden
    if ($result.ExitCode -ne 0) {
      Write-Failure "Legacy installed-app migration failed after activation (exit code: $($result.ExitCode))."
    }
  } catch {
    Write-Failure "Legacy installed-app migration failed after activation: $($_.Exception.Message)"
  }
}

try {
  if (-not $StartupTrigger) {
    throw 'GY activation is boot-only. Restart Windows normally to activate the staged release.'
  }
  if (-not (Test-Path -LiteralPath $pendingPath -PathType Leaf)) {
    Remove-PendingTask
    try { Start-TransientHelperCleanup } catch {}
    exit 0
  }

  $pending = Get-Content -LiteralPath $pendingPath -Raw | ConvertFrom-Json
  if ([int]$pending.schemaVersion -ne 2 -or $null -eq $pending.PSObject.Properties['stagedBootId']) {
    throw 'Pending GY activation does not contain the required boot-bound schema.'
  }
  $dll = [string]$pending.dll
  $hostPath = [string]$pending.host
  $health = [string]$pending.health
  $version = [string]$pending.version
  $previousDll = [string]$pending.previousDll
  $previousHost = [string]$pending.previousHost
  $previousHealth = [string]$pending.previousHealth
  $previousVersion = [string]$pending.previousVersion
  $firstInstall = [bool]$pending.firstInstall
  $stagedBootId = [uint32]$pending.stagedBootId

  if ((Get-CurrentBootId) -eq $stagedBootId) {
    throw 'Windows has not completed a new boot since this GY release was staged.'
  }

  if (-not (Test-ManagedPath $dll) -or -not (Test-ManagedPath $hostPath) -or
      -not (Test-ManagedPath $health) -or -not $version -or
      -not (Test-Path -LiteralPath $dll -PathType Leaf) -or
      -not (Test-Path -LiteralPath $hostPath -PathType Leaf) -or
      -not (Test-Path -LiteralPath $health -PathType Leaf)) {
    throw 'Pending GY activation references missing or unmanaged files.'
  }

  if ($firstInstall) {
    if ($previousVersion -or $previousDll -or $previousHost -or $previousHealth) {
      throw 'First-install activation contains an unexpected rollback snapshot.'
    }
    Assert-NoRegisteredGyState 'First-install activation'
  } else {
    if (-not $previousVersion -or -not (Test-ManagedPath $previousDll) -or
        -not (Test-ManagedPath $previousHost) -or -not (Test-ManagedPath $previousHealth) -or
        -not (Test-Path -LiteralPath $previousDll -PathType Leaf) -or
        -not (Test-Path -LiteralPath $previousHost -PathType Leaf) -or
        -not (Test-Path -LiteralPath $previousHealth -PathType Leaf)) {
      throw 'Pending GY activation rollback state is missing or unmanaged.'
    }
    # The old registration must still be exactly the snapshot we staged. If it
    # changed while this task waited for boot, refuse to overwrite it.
    Assert-OfflineHealthy $previousHealth 'Previous GY rollback target'
    Assert-RegisteredGyState $previousDll $previousHost $previousVersion 'Previous GY rollback target'
  }

  Assert-OfflineHealthy $health 'Pending GY activation target'

  $registrationChanged = $true
  $register = Start-Process -FilePath $regsvr32 -ArgumentList ('/s "{0}"' -f $dll) -Wait -PassThru
  if ($register.ExitCode -ne 0) { throw "Pending GY TSF registration failed (regsvr32 exit code: $($register.ExitCode))." }

  $hostKey = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('Software\GYInput')
  try {
    $hostKey.SetValue('HostPath', $hostPath, [Microsoft.Win32.RegistryValueKind]::String)
    $hostKey.SetValue('HostVersion', $version, [Microsoft.Win32.RegistryValueKind]::String)
  } finally { $hostKey.Dispose() }
  Assert-RegisteredGyState $dll $hostPath $version 'Pending GY activation target'
  Write-VerifiedActiveState $version $dll $hostPath $health $previousVersion
  Invoke-LegacyInstallMigration $version

  if (Test-Path -LiteralPath $prunePath -PathType Leaf) {
    $keep = $version
    if ($previousVersion) { $keep += ',' + $previousVersion }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $prunePath -InstallRoot $installRoot -KeepVersions $keep *> $null
  }
  Remove-Item -LiteralPath $pendingPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $errorPath -Force -ErrorAction SilentlyContinue
  Remove-PendingTask
  # Cleanup starts after the durable state and task removal. A cleanup failure
  # must not roll back a successfully verified registration.
  try { Start-TransientHelperCleanup } catch {}
  exit 0
} catch {
  # If registration succeeded but a later verification/write failed, restore
  # the previous verified registration so the machine never remains half-active.
  try {
    if ($registrationChanged -and $pending -and $firstInstall) {
      $null = Start-Process -FilePath $regsvr32 -ArgumentList ('/s /u "{0}"' -f $dll) -Wait -PassThru
      $registeredHost = Read-RegisteredString 'Software\GYInput' 'HostPath'
      if (Test-SamePath $registeredHost $hostPath) {
        $hostKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('Software\GYInput', $true)
        if ($hostKey) {
          try {
            $hostKey.DeleteValue('HostPath', $false)
            $hostKey.DeleteValue('HostVersion', $false)
          } finally { $hostKey.Dispose() }
        }
      }
    } elseif ($registrationChanged -and $pending -and $previousDll -and (Test-ManagedPath $previousDll) -and
        (Test-ManagedPath $previousHost) -and (Test-ManagedPath $previousHealth) -and
        (Test-Path -LiteralPath $previousDll -PathType Leaf) -and
        (Test-Path -LiteralPath $previousHost -PathType Leaf) -and
        (Test-Path -LiteralPath $previousHealth -PathType Leaf)) {
      $restore = Start-Process -FilePath $regsvr32 -ArgumentList ('/s "{0}"' -f $previousDll) -Wait -PassThru
      if ($restore.ExitCode -eq 0 -and $previousHost) {
        $hostKey = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('Software\GYInput')
        try {
          $hostKey.SetValue('HostPath', $previousHost, [Microsoft.Win32.RegistryValueKind]::String)
          $hostKey.SetValue('HostVersion', $previousVersion, [Microsoft.Win32.RegistryValueKind]::String)
        } finally { $hostKey.Dispose() }
        Assert-RegisteredGyState $previousDll $previousHost $previousVersion 'Recovered previous GY version'
        Write-VerifiedActiveState $previousVersion $previousDll $previousHost $previousHealth $version
      }
    }
  } catch {}
  Write-Failure $_.Exception.Message
  exit 1
} finally {
  if ($mutex) {
    if ($lockTaken) { try { $mutex.ReleaseMutex() } catch {} }
    $mutex.Dispose()
  }
}
