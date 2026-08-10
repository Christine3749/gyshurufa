param(
  [switch]$Uninstall,
  [switch]$Rollback,
  [switch]$Elevated
)

$ErrorActionPreference = 'Stop'
if ($Uninstall -and $Rollback) { throw 'Uninstall and Rollback cannot be used together.' }
$tipId = '0804:{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}{5F689D3E-73E3-4C2B-979A-2DD86E438D6F}'
$packageRoot = $PSScriptRoot
. (Join-Path $packageRoot 'GYInputTransaction.ps1')
$payloadRoot = Join-Path $packageRoot 'payload'
$version = (Get-Content -LiteralPath (Join-Path $packageRoot 'VERSION') -Raw).Trim()
$tsfVersion = $version
if ($version -ne $tsfVersion) { throw "Release version mismatch: Host=$version, Core=$tsfVersion. Refusing mixed installation." }
$programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$installRoot = Join-Path $programFiles 'GYInput'
$versionRoot = Join-Path (Join-Path $installRoot 'versions') $version
$tsfRoot = Join-Path $installRoot ("tsf-$tsfVersion")
$installedDll = Join-Path $tsfRoot 'GyIme.dll'
$installedHost = Join-Path $versionRoot ("GyImeHost-$version.exe")
$installedHealth = Join-Path $versionRoot ("GyImeHealth-$version.exe")
$installedIcon = Join-Path $tsfRoot 'gy.ico'
$installedHostIcon = Join-Path $versionRoot 'gy.ico'
$installedSharedIcon = Join-Path $installRoot 'gy.ico'
$installedNotes = Join-Path $versionRoot 'RELEASE-NOTES.txt'
$pendingPath = Join-Path $installRoot 'pending-activation.json'
$statePath = Join-Path $installRoot 'install-state.json'
$commonDataRoot = Join-Path $env:ProgramData 'GYInput'
$finalizerSource = Join-Path $packageRoot 'Finalize-GYClientReload.ps1'
$pruneSource = Join-Path $packageRoot 'Prune-GYOldVersions.ps1'
$taskRegistrarSource = Join-Path $packageRoot 'Register-GYInputActivationTasks.ps1'
$commonFinalizer = Join-Path $commonDataRoot 'Finalize-GYClientReload.ps1'
$commonPrune = Join-Path $commonDataRoot 'Prune-GYOldVersions.ps1'
$pendingTaskName = 'GYInput\ActivatePending'
$pendingTaskNameLogon = 'GYInput\ActivatePendingLogon'

function Get-X64RegSvr32 {
  if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { return Join-Path $env:WINDIR 'Sysnative\regsvr32.exe' }
  return Join-Path $env:WINDIR 'System32\regsvr32.exe'
}

function Should-PreserveExistingPendingHelpers {
  $activeVersion = Get-ActiveGyHostVersion
  if ([string]::IsNullOrWhiteSpace([string]$activeVersion)) { return $false }
  $existingTransaction = Join-Path $commonDataRoot 'GYInputTransaction.ps1'
  $existingRegistrar = Join-Path $commonDataRoot 'Register-GYInputActivationTasks.ps1'
  if (-not ((Test-Path -LiteralPath $commonFinalizer -PathType Leaf) -and
            (Test-Path -LiteralPath $commonPrune -PathType Leaf) -and
            (Test-Path -LiteralPath $existingTransaction -PathType Leaf) -and
            (Test-Path -LiteralPath $existingRegistrar -PathType Leaf))) {
    return $false
  }
  try { return ([version]$activeVersion -gt [version]$version) }
  catch { throw "无法比较当前激活版本 $activeVersion 与待安装版本 $version；拒绝修改共享激活助手。" }
}

function Install-PendingActivationAssets {
  if (-not (Test-Path -LiteralPath $finalizerSource -PathType Leaf) -or
      -not (Test-Path -LiteralPath $pruneSource -PathType Leaf) -or
      -not (Test-Path -LiteralPath $taskRegistrarSource -PathType Leaf) -or
      -not (Test-Path -LiteralPath (Join-Path $packageRoot 'GYInputTransaction.ps1') -PathType Leaf)) {
    throw 'Pending activation helper files are missing from the ZIP package.'
  }
  New-Item -ItemType Directory -Path $commonDataRoot -Force | Out-Null
  if (Should-PreserveExistingPendingHelpers) {
    $existingTransaction = Join-Path $commonDataRoot 'GYInputTransaction.ps1'
    $existingRegistrar = Join-Path $commonDataRoot 'Register-GYInputActivationTasks.ps1'
    if ((Test-Path -LiteralPath $commonFinalizer -PathType Leaf) -and
        (Test-Path -LiteralPath $commonPrune -PathType Leaf) -and
        (Test-Path -LiteralPath $existingTransaction -PathType Leaf) -and
        (Test-Path -LiteralPath $existingRegistrar -PathType Leaf)) {
      Write-Host "当前激活版本高于待安装版本 $version；保留现有共享激活助手，拒绝降级。"
      return
    }
    throw '当前激活版本较新，但共享激活助手不完整；拒绝继续，当前激活状态保持不变。'
  }
  Copy-Item -LiteralPath $finalizerSource -Destination $commonFinalizer -Force
  Copy-Item -LiteralPath $taskRegistrarSource -Destination (Join-Path $commonDataRoot 'Register-GYInputActivationTasks.ps1') -Force
  Copy-Item -LiteralPath (Join-Path $packageRoot 'GYInputTransaction.ps1') -Destination (Join-Path $commonDataRoot 'GYInputTransaction.ps1') -Force
  Copy-Item -LiteralPath $pruneSource -Destination $commonPrune -Force
}

function Save-PendingActivation([object]$PreviousState) {
  $pending = [ordered]@{
    activationState = 'pending'
    schemaVersion = 1
    version = $version
    dll = $installedDll
    host = $installedHost
    health = $installedHealth
    previousDll = [string]$PreviousState.dll
    previousHost = [string]$PreviousState.host
    previousHealth = [string]$PreviousState.health
    previousVersion = [string]$PreviousState.version
  }

  Write-GyStateAtomically $pending $pendingPath
}

function Test-PendingActivationTargetsThisRelease {
  if (-not (Test-Path -LiteralPath $pendingPath -PathType Leaf)) { return $false }
  try {
    $pending = Get-Content -LiteralPath $pendingPath -Raw | ConvertFrom-Json
    return [string]::Equals([string]$pending.version, $version, [StringComparison]::OrdinalIgnoreCase)
  } catch {
    throw '待激活状态文件无法读取；拒绝卸载或修改其他版本的激活事务。'
  }
}

function Test-ScheduledTaskExists([string]$TaskName) {
  $schtasks = Join-Path $env:WINDIR 'System32\schtasks.exe'
  $probe = Start-Process -FilePath $schtasks -ArgumentList ('/Query /TN "' + $TaskName + '"') -Wait -PassThru -WindowStyle Hidden
  return $probe.ExitCode -eq 0
}

function Register-PendingActivationTask([string]$TaskName, [string]$Schedule) {
  $schtasks = Join-Path $env:WINDIR 'System32\schtasks.exe'
  $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $taskArgs = '/Create /TN "' + $TaskName +
              '" /SC ' + $Schedule + ' /RU SYSTEM /RL HIGHEST /F /TR "' +
              $powershell + ' -NoProfile -ExecutionPolicy Bypass -File ' + $commonFinalizer + '"'
  $result = Start-Process -FilePath $schtasks -ArgumentList $taskArgs -Wait -PassThru
  if ($result.ExitCode -ne 0) { throw "Unable to schedule pending GY activation via $Schedule (schtasks exit code: $($result.ExitCode))." }
  # schtasks has been observed to report success while the task fails to
  # persist (the exact failure mode that left a previous release stuck on
  # its old DLL forever). Read the task back before trusting it.
  if (-not (Wait-GYInputScheduledTask $TaskName)) { throw "Scheduled activation task '$TaskName' did not persist after creation." }
}

function Schedule-PendingActivation {
  try {
    # ONSTART is the primary trigger. ONLOGON is a redundant fallback: with
    # Windows Fast Startup enabled, a plain shutdown-then-power-on resumes a
    # hibernated kernel session instead of a full boot, and ONSTART triggers
    # can silently fail to fire. Both run the same idempotent finalizer;
    # whichever runs first wins and the other becomes a no-op.
    if (-not (Test-Path -LiteralPath $taskRegistrarSource -PathType Leaf)) {
      throw 'Pending activation task registrar is missing from the ZIP package.'
    }
    & $taskRegistrarSource -LockAlreadyHeld
  } catch {
    # A failed task registration must not leave a false pending marker behind.
    # Keep the old registry/TSF activation and the staged version directory so
    # the installer can be retried safely, but make validation truthful.
    Cancel-PendingActivation
    throw
  }
}

function Cancel-PendingActivation {
  $schtasks = Join-Path $env:WINDIR 'System32\schtasks.exe'
  Remove-GYInputScheduledTask $pendingTaskName | Out-Null
  Remove-GYInputScheduledTask $pendingTaskNameLogon | Out-Null
  Remove-Item -LiteralPath $pendingPath -Force -ErrorAction SilentlyContinue
}

function Repair-PendingActivation {
  if (-not (Test-Path -LiteralPath $pendingPath -PathType Leaf)) { return }
  # A previously staged upgrade never got applied — its ONSTART/ONLOGON tasks
  # may have been skipped (Fast Startup) or gone missing. Rather than leaving
  # the machine stuck on the old DLL forever, apply it now using the same
  # finalizer the scheduled tasks would have run, before continuing with
  # whatever this invocation of the installer was asked to do.
  if (-not (Test-Path -LiteralPath $finalizerSource -PathType Leaf)) {
    throw 'Existing pending activation cannot be repaired because the finalizer is missing from this package.'
  }
  $repair = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$finalizerSource,'-LockAlreadyHeld') -Wait -PassThru -WindowStyle Hidden
  if ($repair.ExitCode -ne 0 -or (Test-Path -LiteralPath $pendingPath -PathType Leaf)) {
    throw 'Existing pending activation could not be completed; the current installation was not changed.'
  }
}

function Try-FinalizePendingActivation {
  if (-not (Test-Path -LiteralPath $pendingPath -PathType Leaf)) { return $true }
  if (-not (Test-Path -LiteralPath $finalizerSource -PathType Leaf)) {
    Write-Warning 'GY Finalizer is unavailable; the registered startup/logon fallback will complete activation.'
    return $false
  }
  # The installer already owns the shared transaction mutex. Passing
  # -LockAlreadyHeld prevents a second process from racing this transaction.
  $finalizer = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', $finalizerSource, '-LockAlreadyHeld'
  ) -Wait -PassThru -WindowStyle Hidden
  if ($finalizer.ExitCode -eq 0 -and -not (Test-Path -LiteralPath $pendingPath -PathType Leaf)) {
    return $true
  }
  Write-Warning 'GY activation could not finish in the installer; the registered startup/logon fallback will retry automatically.'
  return $false
}
function Test-SameFile([string]$Source, [string]$Destination) {
  if (-not (Test-Path -LiteralPath $Source) -or -not (Test-Path -LiteralPath $Destination)) { return $false }
  $sourceItem = Get-Item -LiteralPath $Source
  $destinationItem = Get-Item -LiteralPath $Destination
  if ($sourceItem.Length -ne $destinationItem.Length) { return $false }
  return (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
}

function Test-SameTree([string]$Source, [string]$Destination) {
  if (-not (Test-Path -LiteralPath $Destination)) { return $false }
  foreach ($file in Get-ChildItem -LiteralPath $Source -File -Recurse) {
    $relative = $file.FullName.Substring($Source.Length).TrimStart('\')
    if (-not (Test-SameFile $file.FullName (Join-Path $Destination $relative))) { return $false }
  }
  return $true
}

function Test-ThisReleaseInstalled {
  return (Test-SameFile (Join-Path $payloadRoot ("GyIme-$version.dll")) $installedDll) -and
         (Test-SameFile (Join-Path $payloadRoot ("GyImeHost-$version.exe")) $installedHost) -and
         (Test-SameFile (Join-Path $payloadRoot ("GyImeHealth-$version.exe")) $installedHealth) -and
         (Test-SameFile (Join-Path $payloadRoot 'gy.ico') $installedIcon) -and
         (Test-SameFile (Join-Path $payloadRoot 'gy.ico') $installedHostIcon) -and
         (Test-SameFile (Join-Path $payloadRoot 'release-notes.txt') $installedNotes) -and
         (Test-SameFile (Join-Path $payloadRoot 'rime.dll') (Join-Path $versionRoot 'rime.dll')) -and
         (Test-SameTree (Join-Path $payloadRoot 'rime-data') (Join-Path $versionRoot 'rime-data'))
}

function Update-CurrentUserKeyboardList {
  $languages = Get-WinUserLanguageList
  $chinese = $languages | Where-Object LanguageTag -eq 'zh-Hans-CN' | Select-Object -First 1
  if (-not $chinese) { throw '找不到“中文（简体，中国）”。请先在 Windows 设置中添加该语言。' }
  if ($Uninstall) {
    foreach ($language in $languages) { [void]$language.InputMethodTips.Remove($tipId) }
  } else {
    if ($chinese.InputMethodTips -contains $tipId) { [void]$chinese.InputMethodTips.Remove($tipId) }
    # Insert at the front, not appended: Windows treats a language's first tip
    # as its preferred one, and a competing IME (e.g. Tencent WeType) installed
    # either before or after GY would otherwise keep that position indefinitely.
    $chinese.InputMethodTips.Insert(0, $tipId)
  }
  Set-WinUserLanguageList -LanguageList $languages -Force

  if ($Uninstall) {
    try {
      $current = [string](Get-WinDefaultInputMethodOverride)
      if ($current -match '5F689D3D-73E3-4C2B-979A-2DD86E438D6F') { Set-WinDefaultInputMethodOverride }
    } catch {}
  } else {
    # A competing third-party IME can register itself as the cached CTF default
    # for zh-Hans-CN (HKCU\Software\Microsoft\CTF\Assemblies\...\Default). Being
    # present in the language list does not contest that cached default, so GY
    # can stay silently shadowed in every app even though it is fully installed
    # and active. Set-WinDefaultInputMethodOverride is the documented API for
    # the same setting Windows Settings > Language > 选项 > 默认输入法 controls.
    try { Set-WinDefaultInputMethodOverride -InputTip $tipId } catch {}
  }

  # Keep the current language-bar session in sync with the refreshed TSF
  # profile. This script reaches this function from the original interactive
  # user process after any administrator work has completed.
  try {
    if ([Environment]::UserInteractive) {
      $sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
      if ($sessionId -ne 0) {
        $ctfmon = @(Get-Process -Name 'ctfmon' -ErrorAction SilentlyContinue |
          Where-Object { $_.SessionId -eq $sessionId })
        foreach ($process in $ctfmon) {
          Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        if ($ctfmon.Count -gt 0) {
          Start-Sleep -Milliseconds 250
          $ctfmonPath = Join-Path $env:WINDIR 'System32\ctfmon.exe'
          if (Test-Path -LiteralPath $ctfmonPath -PathType Leaf) {
            Start-Process -FilePath $ctfmonPath -WindowStyle Hidden | Out-Null
          }
        }
      }
    }
  } catch {
    # Input-indicator refresh is best effort; it must not invalidate a
    # verified installation or rollback.
  }
}

function Invoke-InstalledValidation {
  $validator = Join-Path $installRoot 'Validate-GYInput.ps1'
  if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) { return $false }
  $result = Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $validator) -Wait -PassThru -WindowStyle Hidden
  return $result.ExitCode -eq 0
}

function Assert-Payload {
  $manifest = Join-Path $payloadRoot 'SHA256SUMS.txt'
  if (-not (Test-Path -LiteralPath $manifest)) { throw '发布包缺少 SHA-256 校验清单。' }
  foreach ($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line -split '  ', 2
    if ($parts.Count -ne 2) { throw '发布包校验清单格式错误。' }
    $file = Join-Path $payloadRoot $parts[1]
    if (-not (Test-Path -LiteralPath $file)) { throw "发布包文件缺失：$($parts[1])" }
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $parts[0]) { throw "发布包完整性校验失败：$($parts[1])" }
  }
}

function Get-ActiveGyDll {
  $keyPath = 'Software\Classes\CLSID\{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}\InprocServer32'
  $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($keyPath)
  if (-not $key) { return $null }
  try { return [string]$key.GetValue('') } finally { $key.Dispose() }
}

function Get-ActiveGyHost {
  $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('Software\GYInput')
  if (-not $key) { return $null }
  try { return [string]$key.GetValue('HostPath') } finally { $key.Dispose() }
}

function Get-ActiveGyHostVersion {
  $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('Software\GYInput')
  if (-not $key) { return $null }
  try { return [string]$key.GetValue('HostVersion') } finally { $key.Dispose() }
}

function Test-ManagedGyPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  try {
    $root = [IO.Path]::GetFullPath($installRoot).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath($Path)
    return $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)
  } catch { return $false }
}

function Get-ActiveGyState {
  $hostPath = Get-ActiveGyHost
  $hostVersion = Get-ActiveGyHostVersion
  $health = $null
  if ($hostPath -and $hostVersion) {
    $health = Join-Path (Split-Path -Parent $hostPath) ("GyImeHealth-" + $hostVersion + ".exe")
  }
  $dll = Get-ActiveGyDll
  return [ordered]@{
    schemaVersion = 2
    dll = $dll
    host = $hostPath
    version = $hostVersion
    coreVersion = Get-CoreVersionFromDllPath $dll
    health = $health
    activationState = 'captured-active-registry'
    capturedAtUtc = [DateTime]::UtcNow.ToString('o')
  }
}

function Set-ActiveGyHostValue([string]$HostPath, [string]$HostVersion) {
  if (-not (Test-ManagedGyPath $HostPath)) { throw 'Refusing to activate a Host outside the managed GYInput directory.' }
  $key = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('Software\GYInput')
  try {
    $key.SetValue('HostPath', $HostPath, [Microsoft.Win32.RegistryValueKind]::String)
    $key.SetValue('HostVersion', $HostVersion, [Microsoft.Win32.RegistryValueKind]::String)
  } finally { $key.Dispose() }
}

function Set-ActiveGyHost {
  Set-ActiveGyHostValue $installedHost $version
}


function Get-CoreVersionFromDllPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
  if ($Path -match '\\tsf-(\d+\.\d+\.\d+)\\GyIme\.dll$') { return $matches[1] }
  return ''
}

function Test-ThisReleaseActive {
  $activeDll = Get-ActiveGyDll
  $activeHost = Get-ActiveGyHost
  $activeHostVersion = Get-ActiveGyHostVersion
  return (Test-ThisReleaseInstalled) -and
         [string]::Equals($activeDll, $installedDll, [StringComparison]::OrdinalIgnoreCase) -and
         [string]::Equals($activeHost, $installedHost, [StringComparison]::OrdinalIgnoreCase) -and
         [string]::Equals($activeHostVersion, $version, [StringComparison]::Ordinal) -and
         (Test-Path -LiteralPath $activeDll -PathType Leaf) -and
         (Test-Path -LiteralPath $activeHost -PathType Leaf)
}

function Write-GyActivationState([string]$ActivationState, [string]$PreviousVersion) {
  $state = [ordered]@{
    schemaVersion = 2
    version = $version
    hostVersion = $version
    coreVersion = $tsfVersion
    installedAtUtc = [DateTime]::UtcNow.ToString('o')
    dll = $installedDll
    host = $installedHost
    health = $installedHealth
    updateModel = 'versioned-tsf-host'
    activationState = $ActivationState
    registryVerified = $ActivationState -eq 'active'
    requiresClientReload = $ActivationState -in @('staged', 'pending')
    previousCoreVersion = $PreviousVersion
  }
  Write-GyStateAtomically $state $statePath
}

function Write-GyStateAtomically([object]$State, [string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { throw 'GY activation state path is required.' }
  $directory = Split-Path -Parent $Path
  $temporary = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
  try {
    [IO.File]::WriteAllText($temporary, ($State | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
  }
}
function Save-PreviousGyState([object]$State) {
  if (-not $State -or -not (Test-ManagedGyPath ([string]$State.dll)) -or
      -not (Test-ManagedGyPath ([string]$State.host)) -or
      -not (Test-ManagedGyPath ([string]$State.health)) -or
      -not (Test-Path -LiteralPath ([string]$State.dll) -PathType Leaf) -or
      -not (Test-Path -LiteralPath ([string]$State.host) -PathType Leaf) -or
      -not (Test-Path -LiteralPath ([string]$State.health) -PathType Leaf) -or
      [string]::IsNullOrWhiteSpace([string]$State.version)) { return }
  $previousPath = Join-Path $installRoot 'install-state.previous.json'
  Write-GyStateAtomically $State $previousPath
}

function Restore-PreviousGyState {
  $previousPath = Join-Path $installRoot 'install-state.previous.json'
  if (-not (Test-Path -LiteralPath $previousPath -PathType Leaf)) {
    throw 'No verified previous GY version is available for rollback.'
  }
  $previous = Get-Content -LiteralPath $previousPath -Raw | ConvertFrom-Json
  $dll = [string]$previous.dll
  $hostPath = [string]$previous.host
  $hostVersion = [string]$previous.version
  $health = [string]$previous.health
  if (-not (Test-ManagedGyPath $dll) -or -not (Test-ManagedGyPath $hostPath) -or
      -not (Test-ManagedGyPath $health) -or -not (Test-Path -LiteralPath $dll -PathType Leaf) -or
      -not (Test-Path -LiteralPath $hostPath -PathType Leaf) -or -not (Test-Path -LiteralPath $health -PathType Leaf)) {
    throw 'Rollback state is incomplete or references an unmanaged GY file.'
  }
  $healthResult = Start-Process -FilePath $health -WorkingDirectory (Split-Path -Parent $health) -Wait -PassThru
  if ($healthResult.ExitCode -ne 0) { throw "Previous version health check failed; rollback was not applied (exit code: $($healthResult.ExitCode))." }
  $restore = Start-Process -FilePath (Get-X64RegSvr32) -ArgumentList ('/s "{0}"' -f $dll) -Wait -PassThru
  if ($restore.ExitCode -ne 0) { throw "Previous GY TSF connector could not be registered (regsvr32 exit code: $($restore.ExitCode))." }
  Set-ActiveGyHostValue $hostPath $hostVersion
  $currentPath = Join-Path $installRoot 'install-state.json'
  if (Test-Path -LiteralPath $currentPath -PathType Leaf) {
    Copy-Item -LiteralPath $currentPath -Destination (Join-Path $installRoot 'install-state.rolled-back.json') -Force
  }
  $restoredState = [ordered]@{
    schemaVersion = 2
    version = $hostVersion
    hostVersion = $hostVersion
    coreVersion = Get-CoreVersionFromDllPath $dll
    installedAtUtc = [DateTime]::UtcNow.ToString('o')
    dll = $dll
    host = $hostPath
    health = $health
    updateModel = 'versioned-tsf-host'
    activationState = 'active'
    registryVerified = $true
    requiresClientReload = $false
    previousCoreVersion = $null
  }
  Write-GyStateAtomically $restoredState $currentPath
}
function Remove-ActiveGyHostIfCurrent {
  $activeHost = Get-ActiveGyHost
  if (-not [string]::Equals($activeHost, $installedHost, [StringComparison]::OrdinalIgnoreCase)) { return }
  $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('Software\GYInput', $true)
  if (-not $key) { return }
  try {
    $key.DeleteValue('HostPath', $false)
    $key.DeleteValue('HostVersion', $false)
  } finally { $key.Dispose() }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $Elevated) {
  if (-not $Uninstall) {
    Assert-Payload
    if (Test-ThisReleaseActive) {
      Update-CurrentUserKeyboardList
      if (-not (Test-Path -LiteralPath $pendingPath -PathType Leaf) -and -not (Invoke-InstalledValidation)) { Write-Warning '安装后自动校验未通过，请运行 Validate-GYInput.ps1 查看具体项。' }
      Write-Host "GY 输入法 $version 已激活；已确认键盘列表与 DLL / Host 注册表指向。"
      exit 0
    }
  }
  if (-not $isAdmin) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Elevated"
    if ($Uninstall) { $arguments += ' -Uninstall' }
    if ($Rollback) { $arguments += ' -Rollback' }
    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "GY 系统安装操作失败；管理员 PowerShell 返回 $($process.ExitCode)。" }
    Update-CurrentUserKeyboardList
    if (-not $Uninstall -and -not $Rollback -and -not (Test-Path -LiteralPath $pendingPath -PathType Leaf) -and -not (Invoke-InstalledValidation)) { Write-Warning '安装后自动校验未通过，请运行 Validate-GYInput.ps1 查看具体项。' }
    if ($Uninstall) { Write-Host 'GY 输入法已从当前账户的键盘列表移除。' }
    elseif ($Rollback) { Write-Host 'GY 输入法已回滚到上一个已验证版本。关闭并重新打开正在输入的应用即可生效。' }
    else {
      $newState = $null
      $newStatePath = Join-Path $installRoot 'install-state.json'
      if (Test-Path -LiteralPath $newStatePath) { $newState = Get-Content -LiteralPath $newStatePath -Raw | ConvertFrom-Json }
      if (Test-Path -LiteralPath $pendingPath -PathType Leaf) {
        Write-Host 'GY 输入法新版核心已暂存；请重启 Windows，重启时会自动激活新版并清理旧版本。重启前继续使用当前版本。'
      } elseif ($newState -and $newState.requiresClientReload -eq $true) {
        Write-Host 'GY 输入法已安装并激活新版本核心，但检测到已打开的应用可能仍在使用旧版 DLL。请关闭并重新打开正在输入的应用；若仍显示旧版本，再重启 Windows。'
      } else {
        Write-Host 'GY 输入法已安装。按 Win + Space，选择“GY 输入法（拼音）”。'
      }
    }
    exit 0
  }
}
if (-not $isAdmin) { throw '注册系统输入法需要管理员权限。' }

$regsvr32 = Get-X64RegSvr32
Invoke-WithGYInputTransaction {
if ($Rollback) {
  Cancel-PendingActivation
  Restore-PreviousGyState
  return
}
if ($Uninstall) {
  if ((Test-Path -LiteralPath $pendingPath -PathType Leaf) -and
      -not (Test-PendingActivationTargetsThisRelease) -and
      -not [string]::Equals((Get-ActiveGyDll), $installedDll, [StringComparison]::OrdinalIgnoreCase)) {
    throw "检测到其他版本正在进行激活事务；卸载 $version 已停止，未删除其他版本的 pending 或任务。"
  }
  Cancel-PendingActivation
  $activeDll = Get-ActiveGyDll
  if ($activeDll -and $activeDll.StartsWith($installRoot, [StringComparison]::OrdinalIgnoreCase)) {
    if (-not [string]::Equals($activeDll, $installedDll, [StringComparison]::OrdinalIgnoreCase)) {
      throw "检测到当前启用的是较新版本：${activeDll}。请从 Windows 已安装的应用卸载当前版本，以免误移除它的键盘入口。"
    }
    if (Test-Path -LiteralPath $activeDll) {
      $process = Start-Process -FilePath $regsvr32 -ArgumentList ('/s /u "{0}"' -f $activeDll) -Wait -PassThru
      if ($process.ExitCode -ne 0) { throw "GY 输入法注销失败；regsvr32 返回 $($process.ExitCode)。" }
    }
  }
  Remove-ActiveGyHostIfCurrent
  return
}

Repair-PendingActivation
Assert-Payload
New-Item -ItemType Directory -Path $versionRoot, $tsfRoot -Force | Out-Null
$payloadDll = Join-Path $payloadRoot ("GyIme-$version.dll")
$payloadHost = Join-Path $payloadRoot ("GyImeHost-$version.exe")
$payloadHealth = Join-Path $payloadRoot ("GyImeHealth-$version.exe")
$payloadIcon = Join-Path $payloadRoot 'gy.ico'
$payloadNotes = Join-Path $payloadRoot 'release-notes.txt'
$payloadRime = Join-Path $payloadRoot 'rime.dll'
$payloadData = Join-Path $payloadRoot 'rime-data'
if (-not (Test-Path -LiteralPath $installedDll)) { Copy-Item -LiteralPath $payloadDll -Destination $installedDll -Force }
if (-not (Test-SameFile $payloadHost $installedHost)) { Copy-Item -LiteralPath $payloadHost -Destination $installedHost -Force }
if (-not (Test-SameFile $payloadHealth $installedHealth)) { Copy-Item -LiteralPath $payloadHealth -Destination $installedHealth -Force }
if (-not (Test-Path -LiteralPath $installedIcon)) { Copy-Item -LiteralPath $payloadIcon -Destination $installedIcon -Force }
if (-not (Test-SameFile $payloadIcon $installedSharedIcon)) { Copy-Item -LiteralPath $payloadIcon -Destination $installedSharedIcon -Force }
if (-not (Test-Path -LiteralPath $installedNotes)) { Copy-Item -LiteralPath $payloadNotes -Destination $installedNotes -Force }
if (-not (Test-SameFile $payloadIcon $installedHostIcon)) { Copy-Item -LiteralPath $payloadIcon -Destination $installedHostIcon -Force }
if (-not (Test-SameFile $payloadRime (Join-Path $versionRoot 'rime.dll'))) { Copy-Item -LiteralPath $payloadRime -Destination (Join-Path $versionRoot 'rime.dll') -Force }
if (-not (Test-SameTree $payloadData (Join-Path $versionRoot 'rime-data'))) {
  if (Test-Path -LiteralPath (Join-Path $versionRoot 'rime-data')) { Remove-Item -LiteralPath (Join-Path $versionRoot 'rime-data') -Recurse -Force }
  Copy-Item -LiteralPath $payloadData -Destination (Join-Path $versionRoot 'rime-data') -Recurse -Force
}
$health = Start-Process -FilePath $installedHealth -WorkingDirectory $versionRoot -Wait -PassThru
if ($health.ExitCode -ne 0) { throw "GY 输入法离线引擎自检失败；退出码：$($health.ExitCode)。旧版本保持不变。" }
$previousState = Get-ActiveGyState
$previousCoreVersion = ''
$previousCoreVersion = [string]$previousState.coreVersion
if ([string]::IsNullOrWhiteSpace($previousCoreVersion)) {
  $previousCoreVersion = Get-CoreVersionFromDllPath ([string]$previousState.dll)
}
$coreActivationPending = -not [string]::IsNullOrWhiteSpace($previousCoreVersion) -and $previousCoreVersion -ne $tsfVersion
$previousInstallStatePath = Join-Path $installRoot 'install-state.json'
$previousInstallState = if (Test-Path -LiteralPath $previousInstallStatePath -PathType Leaf) {
  Get-Content -LiteralPath $previousInstallStatePath -Raw | ConvertFrom-Json
} else { $null }
if ($coreActivationPending) {
  try {
    Install-PendingActivationAssets
    Save-PreviousGyState $previousState
    Write-GyActivationState 'staged' $previousCoreVersion
    Save-PendingActivation $previousState
    Schedule-PendingActivation
    Write-GyActivationState 'pending' $previousCoreVersion
    [void](Try-FinalizePendingActivation)
    return
  } catch {
    Cancel-PendingActivation
    if ($null -ne $previousInstallState) {
      Write-GyStateAtomically $previousInstallState $previousInstallStatePath
    } else {
      Remove-Item -LiteralPath $previousInstallStatePath -Force -ErrorAction SilentlyContinue
    }
    throw
  }
}
$process = Start-Process -FilePath $regsvr32 -ArgumentList ('/s "{0}"' -f $installedDll) -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "GY 输入法注册失败；regsvr32 返回 $($process.ExitCode)。" }
try {
  Set-ActiveGyHost
  if (-not (Test-ThisReleaseActive)) { throw 'GY activation verification failed: registry does not point to the staged DLL and Host.' }
  $activationState = if ($coreActivationPending) { 'registered-pending-client-reload' } else { 'active' }
  $state = [ordered]@{
    schemaVersion = 2; version = $version; hostVersion = $version; coreVersion = $tsfVersion
    installedAtUtc = [DateTime]::UtcNow.ToString('o'); dll = $installedDll; host = $installedHost; health = $installedHealth
    updateModel = 'versioned-tsf-host'; activationState = $activationState; registryVerified = $true
    requiresClientReload = $coreActivationPending; previousCoreVersion = $previousCoreVersion
  }
  Write-GyStateAtomically $state (Join-Path $installRoot 'install-state.json')
  Save-PreviousGyState $previousState
} catch {
  if ((Test-ManagedGyPath ([string]$previousState.dll)) -and (Test-ManagedGyPath ([string]$previousState.host)) -and $previousState.version) {
    $null = Start-Process -FilePath $regsvr32 -ArgumentList ('/s "{0}"' -f $previousState.dll) -Wait -PassThru
    Set-ActiveGyHostValue ([string]$previousState.host) ([string]$previousState.version)
  }
}
  throw
}
