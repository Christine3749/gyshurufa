[CmdletBinding()]
param([switch]$Elevated)

# Repair-GYInput.ps1 — the installed, one-click repair path used by the
# Settings > 更新 page.  It only repairs an existing, fully versioned GY
# installation; it never downloads a package and never touches per-user input
# data, clipboard history, image assets, or the DPAPI-protected account session.

$ErrorActionPreference = 'Stop'
$programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$installRoot = Join-Path $programFiles 'GYInput'
$commonDataRoot = Join-Path $env:ProgramData 'GYInput'
$statePath = Join-Path $installRoot 'install-state.json'
$pendingPath = Join-Path $installRoot 'pending-activation.json'
$pendingErrorPath = Join-Path $installRoot 'pending-activation.error.log'
$repairErrorPath = Join-Path $installRoot 'repair.error.log'
$transactionHelper = Join-Path $installRoot 'GYInputTransaction.ps1'
$prunePath = Join-Path $installRoot 'Prune-GYOldVersions.ps1'
$finalizerPath = Join-Path $commonDataRoot 'Finalize-GYClientReload.ps1'
$powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-X64RegSvr32 {
  if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    return Join-Path $env:WINDIR 'Sysnative\regsvr32.exe'
  }
  return Join-Path $env:WINDIR 'System32\regsvr32.exe'
}

function Get-StateString([object]$State, [string]$Name) {
  if (-not $State) { return '' }
  $property = $State.PSObject.Properties[$Name]
  return if ($property) { [string]$property.Value } else { '' }
}

function Test-ManagedGyPath([string]$Path) {
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

function Write-GyStateAtomically([object]$State) {
  $temporary = Join-Path $installRoot ('.install-state.json.' + [Guid]::NewGuid().ToString('N') + '.tmp')
  try {
    [IO.File]::WriteAllText($temporary, ($State | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $statePath -Force
  } finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) {
      Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
  }
}

function Read-RegisteredString([string]$SubKey, [string]$ValueName) {
  $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($SubKey)
  if (-not $key) { return '' }
  try { return [string]$key.GetValue($ValueName) } finally { $key.Dispose() }
}

function Complete-PendingActivation {
  if (-not (Test-Path -LiteralPath $pendingPath -PathType Leaf)) { return }
  if (-not (Test-Path -LiteralPath $finalizerPath -PathType Leaf)) {
    throw '检测到待激活版本，但缺少 Finalizer；请重新运行同版本或更高版本安装包。'
  }
  $result = Start-Process -FilePath $powershell -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $finalizerPath, '-LockAlreadyHeld'
  ) -Wait -PassThru -WindowStyle Hidden
  if ($result.ExitCode -ne 0 -or (Test-Path -LiteralPath $pendingPath -PathType Leaf)) {
    throw '待激活版本未能完成；当前活动版本与诊断文件已保留。'
  }
}

function Remove-StaleTransientHelpers {
  # These are staging-only helpers.  The installed repair tool intentionally
  # remains in Program Files so the user can invoke it again later.
  if (Test-Path -LiteralPath $pendingPath -PathType Leaf) { return }
  Remove-GYInputScheduledTask 'GYInput\ActivatePending' | Out-Null
  Remove-GYInputScheduledTask 'GYInput\ActivatePendingLogon' | Out-Null
  foreach ($name in @(
    'Finalize-GYClientReload.ps1',
    'Prune-GYOldVersions.ps1',
    'GYInputTransaction.ps1',
    'Register-GYInputActivationTasks.ps1'
  )) {
    Remove-Item -LiteralPath (Join-Path $commonDataRoot $name) -Force -ErrorAction SilentlyContinue
  }
}

if (-not (Test-IsAdministrator)) {
  $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Elevated"
  $elevated = Start-Process -FilePath $powershell -Verb RunAs -ArgumentList $arguments -Wait -PassThru
  exit $elevated.ExitCode
}

try {
  if (-not (Test-Path -LiteralPath $transactionHelper -PathType Leaf)) {
    throw 'GY 安装维护组件不完整；请重新运行同版本或更高版本安装包。'
  }
  if (-not (Test-Path -LiteralPath $prunePath -PathType Leaf)) {
    throw 'GY 旧版本清理组件缺失；请重新运行同版本或更高版本安装包。'
  }
  . $transactionHelper

  Invoke-WithGYInputTransaction {
    Complete-PendingActivation
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
      throw '未找到已安装版本状态；请重新运行同版本或更高版本安装包。'
    }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $version = Get-StateString $state 'version'
    $hostVersion = Get-StateString $state 'hostVersion'
    $coreVersion = Get-StateString $state 'coreVersion'
    $dll = Get-StateString $state 'dll'
    $hostPath = Get-StateString $state 'host'
    $healthPath = Get-StateString $state 'health'
    $previousCoreVersion = Get-StateString $state 'previousCoreVersion'

    if ($version -notmatch '^\d+(\.\d+){2,3}$' -or $hostVersion -ne $version -or $coreVersion -ne $version) {
      throw '已安装状态的 Host / DLL 版本不一致；请重新运行同版本或更高版本安装包。'
    }
    $expectedDll = Join-Path $installRoot ("tsf-$version\GyIme.dll")
    $expectedHost = Join-Path $installRoot ("versions\$version\GyImeHost-$version.exe")
    $expectedHealth = Join-Path $installRoot ("versions\$version\GyImeHealth-$version.exe")
    if (-not (Test-ManagedGyPath $dll) -or -not (Test-ManagedGyPath $hostPath) -or
        -not (Test-ManagedGyPath $healthPath) -or -not (Test-SamePath $dll $expectedDll) -or
        -not (Test-SamePath $hostPath $expectedHost) -or -not (Test-SamePath $healthPath $expectedHealth) -or
        -not (Test-Path -LiteralPath $dll -PathType Leaf) -or -not (Test-Path -LiteralPath $hostPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $healthPath -PathType Leaf)) {
      throw '已安装版本文件不完整或不在 GYInput 管理目录内；未修改注册表。'
    }

    $health = Start-Process -FilePath $healthPath -WorkingDirectory (Split-Path -Parent $healthPath) -Wait -PassThru
    if ($health.ExitCode -ne 0) {
      throw "离线引擎自检失败（退出码：$($health.ExitCode)）；保留现有注册与文件。"
    }

    $register = Start-Process -FilePath (Get-X64RegSvr32) -ArgumentList ('/s "{0}"' -f $dll) -Wait -PassThru
    if ($register.ExitCode -ne 0) {
      throw "TSF DLL 注册失败（regsvr32 退出码：$($register.ExitCode)）。"
    }
    $hostKey = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('Software\GYInput')
    try {
      $hostKey.SetValue('HostPath', $hostPath, [Microsoft.Win32.RegistryValueKind]::String)
      $hostKey.SetValue('HostVersion', $version, [Microsoft.Win32.RegistryValueKind]::String)
    } finally {
      $hostKey.Dispose()
    }

    $registeredDll = Read-RegisteredString 'Software\Classes\CLSID\{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}\InprocServer32' ''
    $registeredHost = Read-RegisteredString 'Software\GYInput' 'HostPath'
    $registeredHostVersion = Read-RegisteredString 'Software\GYInput' 'HostVersion'
    if (-not (Test-SamePath $registeredDll $dll) -or -not (Test-SamePath $registeredHost $hostPath) -or
        $registeredHostVersion -ne $version) {
      throw '注册表写入后校验失败；保留现有文件与诊断信息。'
    }

    $repairedState = [ordered]@{
      schemaVersion = 2
      version = $version
      hostVersion = $version
      coreVersion = $version
      installedAtUtc = [DateTime]::UtcNow.ToString('o')
      dll = $dll
      host = $hostPath
      health = $healthPath
      updateModel = 'versioned-tsf-host'
      activationState = 'active'
      registryVerified = $true
      requiresClientReload = $false
      previousCoreVersion = if ($previousCoreVersion -match '^\d+(\.\d+){2,3}$') { $previousCoreVersion } else { $null }
    }
    Write-GyStateAtomically $repairedState
    Remove-Item -LiteralPath $pendingPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $pendingErrorPath -Force -ErrorAction SilentlyContinue

    $keep = $version
    if ($repairedState.previousCoreVersion) { $keep += ',' + $repairedState.previousCoreVersion }
    $prune = Start-Process -FilePath $powershell -ArgumentList @(
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $prunePath,
      '-InstallRoot', $installRoot, '-KeepVersions', $keep
    ) -Wait -PassThru -WindowStyle Hidden
    if ($prune.ExitCode -ne 0) {
      throw "旧版本清理器异常退出（退出码：$($prune.ExitCode)）。"
    }
    Remove-StaleTransientHelpers
  }

  Remove-Item -LiteralPath $repairErrorPath -Force -ErrorAction SilentlyContinue
  Write-Host 'GY 修复完成：当前版本已校验，旧版本和失效临时安装文件已清理。' -ForegroundColor Green
  exit 0
} catch {
  try {
    "{0} {1}" -f [DateTime]::UtcNow.ToString('o'), $_.Exception.Message |
      Set-Content -LiteralPath $repairErrorPath -Encoding utf8
  } catch {}
  Write-Error $_.Exception.Message
  exit 1
}
