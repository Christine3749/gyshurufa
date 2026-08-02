param(
  [switch]$Uninstall,
  [switch]$Rollback,
  [switch]$Elevated
)

$ErrorActionPreference = 'Stop'
if ($Uninstall -and $Rollback) { throw 'Uninstall and Rollback cannot be used together.' }
$tipId = '0804:{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}{5F689D3E-73E3-4C2B-979A-2DD86E438D6F}'
$packageRoot = $PSScriptRoot
$payloadRoot = Join-Path $packageRoot 'payload'
$version = (Get-Content -LiteralPath (Join-Path $packageRoot 'VERSION') -Raw).Trim()
$tsfVersion = '0.9.12'
if ($version -ne $tsfVersion) { throw "Release version mismatch: Host=$version, Core=$tsfVersion. Refusing mixed installation." }
$programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$installRoot = Join-Path $programFiles 'GYInput'
$versionRoot = Join-Path (Join-Path $installRoot 'versions') $version
$tsfRoot = Join-Path $installRoot ("tsf-$tsfVersion")
$installedDll = Join-Path $tsfRoot 'GyIme.dll'
$installedHost = Join-Path $versionRoot ("GyImeHost-$version.exe")
$installedHealth = Join-Path $versionRoot ("GyImeHealth-$version.exe")
$installedIcon = Join-Path $tsfRoot 'gy.ico'

function Get-X64RegSvr32 {
  if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { return Join-Path $env:WINDIR 'Sysnative\regsvr32.exe' }
  return Join-Path $env:WINDIR 'System32\regsvr32.exe'
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
         (Test-SameFile (Join-Path $payloadRoot 'rime.dll') (Join-Path $versionRoot 'rime.dll')) -and
         (Test-SameTree (Join-Path $payloadRoot 'rime-data') (Join-Path $versionRoot 'rime-data'))
}

function Update-CurrentUserKeyboardList {
  $languages = Get-WinUserLanguageList
  $chinese = $languages | Where-Object LanguageTag -eq 'zh-Hans-CN' | Select-Object -First 1
  if (-not $chinese) { throw '找不到“中文（简体，中国）”。请先在 Windows 设置中添加该语言。' }
  if ($Uninstall) {
    foreach ($language in $languages) { [void]$language.InputMethodTips.Remove($tipId) }
  } elseif ($chinese.InputMethodTips -notcontains $tipId) {
    [void]$chinese.InputMethodTips.Add($tipId)
  }
  Set-WinUserLanguageList -LanguageList $languages -Force
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
  $host = Get-ActiveGyHost
  $hostVersion = Get-ActiveGyHostVersion
  $health = $null
  if ($host -and $hostVersion) {
    $health = Join-Path (Split-Path -Parent $host) ("GyImeHealth-" + $hostVersion + ".exe")
  }
  return [ordered]@{
    dll = Get-ActiveGyDll
    host = $host
    version = $hostVersion
    health = $health
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

function Save-PreviousGyState([object]$State) {
  if (-not $State -or -not (Test-ManagedGyPath ([string]$State.dll)) -or
      -not (Test-ManagedGyPath ([string]$State.host)) -or
      [string]::IsNullOrWhiteSpace([string]$State.version)) { return }
  $previousPath = Join-Path $installRoot 'install-state.previous.json'
  $State | ConvertTo-Json | Set-Content -LiteralPath $previousPath -Encoding utf8
}

function Restore-PreviousGyState {
  $previousPath = Join-Path $installRoot 'install-state.previous.json'
  if (-not (Test-Path -LiteralPath $previousPath -PathType Leaf)) {
    throw 'No verified previous GY version is available for rollback.'
  }
  $previous = Get-Content -LiteralPath $previousPath -Raw | ConvertFrom-Json
  $dll = [string]$previous.dll
  $host = [string]$previous.host
  $hostVersion = [string]$previous.version
  $health = [string]$previous.health
  if (-not (Test-ManagedGyPath $dll) -or -not (Test-ManagedGyPath $host) -or
      -not (Test-ManagedGyPath $health) -or -not (Test-Path -LiteralPath $dll -PathType Leaf) -or
      -not (Test-Path -LiteralPath $host -PathType Leaf) -or -not (Test-Path -LiteralPath $health -PathType Leaf)) {
    throw 'Rollback state is incomplete or references an unmanaged GY file.'
  }
  $healthResult = Start-Process -FilePath $health -WorkingDirectory (Split-Path -Parent $health) -Wait -PassThru
  if ($healthResult.ExitCode -ne 0) { throw "Previous version health check failed; rollback was not applied (exit code: $($healthResult.ExitCode))." }
  $restore = Start-Process -FilePath (Get-X64RegSvr32) -ArgumentList ('/s "{0}"' -f $dll) -Wait -PassThru
  if ($restore.ExitCode -ne 0) { throw "Previous GY TSF connector could not be registered (regsvr32 exit code: $($restore.ExitCode))." }
  Set-ActiveGyHostValue $host $hostVersion
  $currentPath = Join-Path $installRoot 'install-state.json'
  if (Test-Path -LiteralPath $currentPath -PathType Leaf) {
    Copy-Item -LiteralPath $currentPath -Destination (Join-Path $installRoot 'install-state.rolled-back.json') -Force
  }
  $previous | ConvertTo-Json | Set-Content -LiteralPath $currentPath -Encoding utf8
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
    if (Test-ThisReleaseInstalled) {
      Update-CurrentUserKeyboardList
      Write-Host "GY 输入法 $version 已安装；已确认键盘列表。"
      exit 0
    }
  }
  $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Elevated"
  if ($Uninstall) { $arguments += ' -Uninstall' }
  if ($Rollback) { $arguments += ' -Rollback' }
  $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait -PassThru
  if ($process.ExitCode -ne 0) { throw "GY 系统安装操作失败；管理员 PowerShell 返回 $($process.ExitCode)。" }
  Update-CurrentUserKeyboardList
  if ($Uninstall) { Write-Host 'GY 输入法已从当前账户的键盘列表移除。' }
  elseif ($Rollback) { Write-Host 'GY 输入法已回滚到上一个已验证版本。关闭并重新打开正在输入的应用即可生效。' }
  else { Write-Host 'GY 输入法已安装。按 Win + Space，选择“GY 输入法（拼音）”。' }
  exit 0
}
if (-not $isAdmin) { throw '注册系统输入法需要管理员权限。' }

$regsvr32 = Get-X64RegSvr32
if ($Rollback) {
  Restore-PreviousGyState
  exit 0
}
if ($Uninstall) {
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
  exit 0
}

Assert-Payload
New-Item -ItemType Directory -Path $versionRoot, $tsfRoot -Force | Out-Null
$payloadDll = Join-Path $payloadRoot ("GyIme-$version.dll")
$payloadHost = Join-Path $payloadRoot ("GyImeHost-$version.exe")
$payloadHealth = Join-Path $payloadRoot ("GyImeHealth-$version.exe")
$payloadIcon = Join-Path $payloadRoot 'gy.ico'
$payloadRime = Join-Path $payloadRoot 'rime.dll'
$payloadData = Join-Path $payloadRoot 'rime-data'
if (-not (Test-Path -LiteralPath $installedDll)) { Copy-Item -LiteralPath $payloadDll -Destination $installedDll -Force }
if (-not (Test-SameFile $payloadHost $installedHost)) { Copy-Item -LiteralPath $payloadHost -Destination $installedHost -Force }
if (-not (Test-SameFile $payloadHealth $installedHealth)) { Copy-Item -LiteralPath $payloadHealth -Destination $installedHealth -Force }
if (-not (Test-Path -LiteralPath $installedIcon)) { Copy-Item -LiteralPath $payloadIcon -Destination $installedIcon -Force }
if (-not (Test-SameFile $payloadRime (Join-Path $versionRoot 'rime.dll'))) { Copy-Item -LiteralPath $payloadRime -Destination (Join-Path $versionRoot 'rime.dll') -Force }
if (-not (Test-SameTree $payloadData (Join-Path $versionRoot 'rime-data'))) {
  if (Test-Path -LiteralPath (Join-Path $versionRoot 'rime-data')) { Remove-Item -LiteralPath (Join-Path $versionRoot 'rime-data') -Recurse -Force }
  Copy-Item -LiteralPath $payloadData -Destination (Join-Path $versionRoot 'rime-data') -Recurse -Force
}
$health = Start-Process -FilePath $installedHealth -WorkingDirectory $versionRoot -Wait -PassThru
if ($health.ExitCode -ne 0) { throw "GY 输入法离线引擎自检失败；退出码：$($health.ExitCode)。旧版本保持不变。" }
$previousState = Get-ActiveGyState
$process = Start-Process -FilePath $regsvr32 -ArgumentList ('/s "{0}"' -f $installedDll) -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "GY 输入法注册失败；regsvr32 返回 $($process.ExitCode)。" }
try {
  Set-ActiveGyHost
  @{ version = $version; hostVersion = $version; coreVersion = $tsfVersion; installedAtUtc = [DateTime]::UtcNow.ToString('o'); dll = $installedDll; host = $installedHost; health = $installedHealth; updateModel = 'versioned-tsf-host' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $installRoot 'install-state.json') -Encoding utf8
  Save-PreviousGyState $previousState
} catch {
  if ((Test-ManagedGyPath ([string]$previousState.dll)) -and (Test-ManagedGyPath ([string]$previousState.host)) -and $previousState.version) {
    $null = Start-Process -FilePath $regsvr32 -ArgumentList ('/s "{0}"' -f $previousState.dll) -Wait -PassThru
    Set-ActiveGyHostValue ([string]$previousState.host) ([string]$previousState.version)
  }
  throw
}

