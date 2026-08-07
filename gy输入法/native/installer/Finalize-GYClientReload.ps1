# Finalize-GYClientReload.ps1
param([switch]$LockAlreadyHeld)
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
$taskNameLogon = 'GYInput\ActivatePendingLogon'
$regsvr32 = Join-Path $env:WINDIR 'System32\regsvr32.exe'
$prunePath = Join-Path $commonDataRoot 'Prune-GYOldVersions.ps1'
$errorPath = Join-Path $installRoot 'pending-activation.error.log'

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
    Remove-GYInputScheduledTask $taskNameLogon | Out-Null
  } catch {}
}

function Write-Failure([string]$Message) {
  try {
    $stamp = [DateTime]::UtcNow.ToString('o')
    "$stamp $Message" | Set-Content -LiteralPath $errorPath -Encoding utf8
  } catch {}
}

function Test-ManagedPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  $root = [IO.Path]::GetFullPath($installRoot).TrimEnd('\') + '\'
  $full = [IO.Path]::GetFullPath($Path)
  return $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)
}

try {
  if (-not (Test-Path -LiteralPath $pendingPath -PathType Leaf)) {
    Remove-PendingTask
    exit 0
  }

  $pending = Get-Content -LiteralPath $pendingPath -Raw | ConvertFrom-Json
  $dll = [string]$pending.dll
  $hostPath = [string]$pending.host
  $health = [string]$pending.health
  $version = [string]$pending.version
  $previousDll = [string]$pending.previousDll
  $previousHost = [string]$pending.previousHost
  $previousHealth = [string]$pending.previousHealth
  $previousVersion = [string]$pending.previousVersion

  if (-not (Test-ManagedPath $dll) -or -not (Test-ManagedPath $hostPath) -or
      -not (Test-ManagedPath $health) -or -not $version -or
      -not (Test-Path -LiteralPath $dll -PathType Leaf) -or
      -not (Test-Path -LiteralPath $hostPath -PathType Leaf) -or
      -not (Test-Path -LiteralPath $health -PathType Leaf)) {
    throw 'Pending GY activation references missing or unmanaged files.'
  }

  if (-not $previousVersion -or -not (Test-ManagedPath $previousDll) -or
      -not (Test-ManagedPath $previousHost) -or -not (Test-ManagedPath $previousHealth) -or
      -not (Test-Path -LiteralPath $previousDll -PathType Leaf) -or
      -not (Test-Path -LiteralPath $previousHost -PathType Leaf) -or
      -not (Test-Path -LiteralPath $previousHealth -PathType Leaf)) {
    throw 'Pending GY activation rollback state is missing or unmanaged.'
  }

  $healthResult = Start-Process -FilePath $health -WorkingDirectory (Split-Path -Parent $health) -Wait -PassThru
  if ($healthResult.ExitCode -ne 0) { throw "Pending GY health check failed (exit code: $($healthResult.ExitCode))." }

  $register = Start-Process -FilePath $regsvr32 -ArgumentList ('/s "{0}"' -f $dll) -Wait -PassThru
  if ($register.ExitCode -ne 0) { throw "Pending GY TSF registration failed (regsvr32 exit code: $($register.ExitCode))." }

  $clsid = 'Software\Classes\CLSID\{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}\InprocServer32'
  $activeKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($clsid)
  try {
    $activeDll = if ($activeKey) { [string]$activeKey.GetValue('') } else { '' }
  } finally { if ($activeKey) { $activeKey.Dispose() } }
  if (-not [string]::Equals($activeDll, $dll, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Pending GY activation did not point the registry at the staged DLL.'
  }

  $hostKey = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('Software\GYInput')
  try {
    $hostKey.SetValue('HostPath', $hostPath, [Microsoft.Win32.RegistryValueKind]::String)
    $hostKey.SetValue('HostVersion', $version, [Microsoft.Win32.RegistryValueKind]::String)
  } finally { $hostKey.Dispose() }

  $state = [ordered]@{
    schemaVersion = 2
    version = $version
    hostVersion = $version
    coreVersion = $version
    installedAtUtc = [DateTime]::UtcNow.ToString('o')
    dll = $dll
    host = $hostPath
    health = $health
    updateModel = 'versioned-tsf-host'
    activationState = 'active'
    registryVerified = $true
    requiresClientReload = $false
    previousCoreVersion = $previousVersion
  }
  $temporary = Join-Path $installRoot ('.install-state.json.' + [Guid]::NewGuid().ToString('N') + '.tmp')
  try {
    [IO.File]::WriteAllText($temporary, ($state | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination (Join-Path $installRoot 'install-state.json') -Force
  } finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
  }

  if (Test-Path -LiteralPath $prunePath -PathType Leaf) {
    $keep = $version
    if ($previousVersion) { $keep += ',' + $previousVersion }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $prunePath -InstallRoot $installRoot -KeepVersions $keep *> $null
  }
  Remove-Item -LiteralPath $pendingPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $errorPath -Force -ErrorAction SilentlyContinue
  Remove-PendingTask
  exit 0
} catch {
  # If registration succeeded but a later verification/write failed, restore
  # the previous verified registration so the machine never remains half-active.
  try {
    if ($pending -and $previousDll -and (Test-ManagedPath $previousDll) -and
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
