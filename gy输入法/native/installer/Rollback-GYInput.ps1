param([switch]$Elevated)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'GYInputTransaction.ps1')
$programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$installRoot = Join-Path $programFiles 'GYInput'
$previousPath = Join-Path $installRoot 'install-state.previous.json'
$currentPath = Join-Path $installRoot 'install-state.json'
$pendingPath = Join-Path $installRoot 'pending-activation.json'
$rollbackErrorPath = Join-Path $installRoot 'rollback.error.log'
$recoveryReportPath = Join-Path $installRoot 'recovery-report.json'
$prunePath = Join-Path $installRoot 'Prune-GYOldVersions.ps1'
$powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$taskName = 'GYInput\ActivatePending'
$taskNameLogon = 'GYInput\ActivatePendingLogon'

function Get-X64RegSvr32 {
  if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { return Join-Path $env:WINDIR 'Sysnative\regsvr32.exe' }
  return Join-Path $env:WINDIR 'System32\regsvr32.exe'
}

function Test-ManagedGyPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  try {
    $root = [IO.Path]::GetFullPath($installRoot).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath($Path)
    return $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)
  } catch { return $false }
}

function Set-ActiveGyHost([string]$HostPath, [string]$HostVersion) {
  if (-not (Test-ManagedGyPath $HostPath)) { throw 'Rollback refused: Host is outside the managed GYInput directory.' }
  $key = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('Software\GYInput')
  try {
    $key.SetValue('HostPath', $HostPath, [Microsoft.Win32.RegistryValueKind]::String)
    $key.SetValue('HostVersion', $HostVersion, [Microsoft.Win32.RegistryValueKind]::String)
  } finally { $key.Dispose() }
}


function Write-GyStateAtomically([object]$State, [string]$Path) {
  $directory = Split-Path -Parent $Path
  $temporary = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
  try {
    [IO.File]::WriteAllText($temporary, ($State | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
  }
}

function Get-StateString([object]$State, [string]$Name) {
  if (-not $State) { return '' }
  $property = $State.PSObject.Properties[$Name]
  if ($property) { return [string]$property.Value }
  return ''
}

function Test-SamePath([string]$Left, [string]$Right) {
  return [string]::Equals($Left, $Right, [StringComparison]::OrdinalIgnoreCase)
}

function Read-RegisteredString([string]$SubKey, [string]$ValueName) {
  $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($SubKey)
  if (-not $key) { return '' }
  try { return [string]$key.GetValue($ValueName) } finally { $key.Dispose() }
}

function Test-VerifiedGyState([object]$State) {
  $dll = Get-StateString $State 'dll'
  $hostPath = Get-StateString $State 'host'
  $health = Get-StateString $State 'health'
  $version = Get-StateString $State 'version'
  $activationState = Get-StateString $State 'activationState'
  $registryVerified = $State -and $State.PSObject.Properties['registryVerified'] -and $State.registryVerified -eq $true
  return $activationState -eq 'active' -and $registryVerified -and $version -match '^\d+\.\d+\.\d+$' -and
         (Test-ManagedGyPath $dll) -and (Test-ManagedGyPath $hostPath) -and (Test-ManagedGyPath $health) -and
         (Test-Path -LiteralPath $dll -PathType Leaf) -and
         (Test-Path -LiteralPath $hostPath -PathType Leaf) -and
         (Test-Path -LiteralPath $health -PathType Leaf)
}

function Assert-RegisteredGyState([string]$Dll, [string]$HostPath, [string]$Version) {
  $registeredDll = Read-RegisteredString 'Software\Classes\CLSID\{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}\InprocServer32' ''
  $registeredHost = Read-RegisteredString 'Software\GYInput' 'HostPath'
  $registeredVersion = Read-RegisteredString 'Software\GYInput' 'HostVersion'
  if (-not (Test-SamePath $registeredDll $Dll) -or -not (Test-SamePath $registeredHost $HostPath) -or
      $registeredVersion -ne $Version) {
    throw '回退后的 DLL / Host 注册表校验失败。'
  }
}

function Restart-ActiveGyHost([string]$HostPath) {
  # A rollback is an explicit recovery action. Stop only GY hosts inside the
  # managed install root, then immediately start the verified restored Host.
  # No unrelated process and no user data are touched.
  Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'GyImeHost-*' } | ForEach-Object {
    try {
      if (Test-ManagedGyPath $_.Path) { Stop-Process -Id $_.Id -Force -ErrorAction Stop }
    } catch {}
  }
  $started = Start-Process -FilePath $HostPath -WorkingDirectory (Split-Path -Parent $HostPath) -PassThru
  Start-Sleep -Milliseconds 150
  if ($started.HasExited) { throw "已恢复的 GY Host 未能启动（退出码：$($started.ExitCode)）。" }
}

function Invoke-PostRecoveryCleanup([string]$ActiveVersion, [string]$RetainedVersion) {
  if (-not (Test-Path -LiteralPath $prunePath -PathType Leaf)) { return $false }
  $keep = $ActiveVersion
  if ($RetainedVersion -match '^\d+\.\d+\.\d+$' -and $RetainedVersion -ne $ActiveVersion) {
    $keep += ',' + $RetainedVersion
  }
  $result = Start-Process -FilePath $powershell -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $prunePath,
    '-InstallRoot', $installRoot, '-KeepVersions', $keep
  ) -Wait -PassThru -WindowStyle Hidden
  return $result.ExitCode -eq 0
}

function Write-RecoveryReport([string]$Status, [string]$FromVersion, [string]$ToVersion,
                              [string]$Message, [bool]$CleanupCompleted) {
  $report = [ordered]@{
    schemaVersion = 1
    action = 'rollback'
    status = $Status
    fromVersion = $FromVersion
    toVersion = $ToVersion
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    cleanupCompleted = $CleanupCompleted
    message = $Message
  }
  Write-GyStateAtomically $report $recoveryReportPath
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $Elevated -and -not $isAdmin) {
  $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Elevated"
  $process = Start-Process -FilePath $powershell -Verb RunAs -ArgumentList $arguments -Wait -PassThru
  if ($process.ExitCode -ne 0) { throw "GY rollback failed; elevated PowerShell returned $($process.ExitCode)." }
  Write-Host 'GY 输入法已回退并重新验证。Host 已重启；现在可以直接继续输入。'
  exit 0
}

$fromVersion = ''
$toVersion = ''
try {
  Invoke-WithGYInputTransaction {
    if (-not $isAdmin) { throw 'Rollback requires administrator permission.' }
    $currentState = if (Test-Path -LiteralPath $currentPath -PathType Leaf) {
      Get-Content -LiteralPath $currentPath -Raw | ConvertFrom-Json
    } else { $null }
    $fromVersion = Get-StateString $currentState 'version'
    if (-not (Test-Path -LiteralPath $previousPath -PathType Leaf)) {
      throw '没有可回退的上一已验证版本。'
    }

    $previous = Get-Content -LiteralPath $previousPath -Raw | ConvertFrom-Json
    if (-not (Test-VerifiedGyState $previous)) {
      throw '回退快照不完整、文件缺失或不属于 GYInput 管理目录；未修改当前版本。'
    }
    $dll = Get-StateString $previous 'dll'
    $hostPath = Get-StateString $previous 'host'
    $hostVersion = Get-StateString $previous 'version'
    $health = Get-StateString $previous 'health'
    $toVersion = $hostVersion
    if ($fromVersion -eq $toVersion) {
      throw "当前已是 v$toVersion；没有更早的可回退版本。"
    }

    $healthResult = Start-Process -FilePath $health -WorkingDirectory (Split-Path -Parent $health) -Wait -PassThru
    if ($healthResult.ExitCode -ne 0) {
      throw "回退目标离线引擎自检失败（退出码：$($healthResult.ExitCode)）；未修改当前版本。"
    }

    $registrationChanged = $false
    try {
      $restore = Start-Process -FilePath (Get-X64RegSvr32) -ArgumentList ('/s "{0}"' -f $dll) -Wait -PassThru
      if ($restore.ExitCode -ne 0) {
        throw "回退目标 TSF DLL 注册失败（regsvr32 退出码：$($restore.ExitCode)）。"
      }
      Set-ActiveGyHost $hostPath $hostVersion
      $registrationChanged = $true
      Assert-RegisteredGyState $dll $hostPath $hostVersion

      if ($currentState) {
        Copy-Item -LiteralPath $currentPath -Destination (Join-Path $installRoot 'install-state.rolled-back.json') -Force
      }
      $restoredState = [ordered]@{
        schemaVersion = 2
        version = $hostVersion
        hostVersion = $hostVersion
        coreVersion = [IO.Path]::GetFileName((Split-Path -Parent $dll)).Replace('tsf-','')
        installedAtUtc = [DateTime]::UtcNow.ToString('o')
        dll = $dll
        host = $hostPath
        health = $health
        updateModel = 'versioned-tsf-host'
        activationState = 'active'
        registryVerified = $true
        requiresClientReload = $false
        # Preserve the outgoing version for safe retention and diagnostics;
        # it is not made active and cannot replace the restored target.
        previousCoreVersion = if ($fromVersion -match '^\d+\.\d+\.\d+$') { $fromVersion } else { $null }
        lastRecovery = [ordered]@{ action = 'rollback'; fromVersion = $fromVersion; completedAtUtc = [DateTime]::UtcNow.ToString('o') }
      }
      Write-GyStateAtomically $restoredState $currentPath
      Restart-ActiveGyHost $hostPath

      Remove-GYInputScheduledTask $taskName | Out-Null
      Remove-GYInputScheduledTask $taskNameLogon | Out-Null
      Remove-Item -LiteralPath $pendingPath -Force -ErrorAction SilentlyContinue
      $cleanupCompleted = Invoke-PostRecoveryCleanup $hostVersion $fromVersion
      Write-RecoveryReport 'succeeded' $fromVersion $hostVersion '已回退、重新注册并验证上一健康版本。' $cleanupCompleted
    } catch {
      # A partial rollback must never strand the machine on an unverified
      # registration. Restore the former known-good state when it is complete.
      if ($registrationChanged -and (Test-VerifiedGyState $currentState)) {
        try {
          $restoreCurrent = Start-Process -FilePath (Get-X64RegSvr32) -ArgumentList ('/s "{0}"' -f (Get-StateString $currentState 'dll')) -Wait -PassThru
          if ($restoreCurrent.ExitCode -eq 0) {
            Set-ActiveGyHost (Get-StateString $currentState 'host') (Get-StateString $currentState 'version')
            Assert-RegisteredGyState (Get-StateString $currentState 'dll') (Get-StateString $currentState 'host') (Get-StateString $currentState 'version')
            Write-GyStateAtomically $currentState $currentPath
            Restart-ActiveGyHost (Get-StateString $currentState 'host')
          }
        } catch {}
      }
      throw
    }
  }
  Remove-Item -LiteralPath $rollbackErrorPath -Force -ErrorAction SilentlyContinue
  Write-Host "GY 输入法已安全回退：v$fromVersion → v$toVersion。"
  exit 0
} catch {
  $message = $_.Exception.Message
  try { Write-RecoveryReport 'failed' $fromVersion $toVersion $message $false } catch {}
  try { "{0} {1}" -f [DateTime]::UtcNow.ToString('o'), $message | Set-Content -LiteralPath $rollbackErrorPath -Encoding utf8 } catch {}
  Write-Error $message
  exit 1
}
