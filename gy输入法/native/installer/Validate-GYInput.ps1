[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$tipId = '0804:{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}{5F689D3E-73E3-4C2B-979A-2DD86E438D6F}'
$failures = [System.Collections.Generic.List[string]]::new()

function Check([bool]$condition, [string]$success, [string]$failure) {
  if ($condition) { Write-Host "[通过] $success" -ForegroundColor Green }
  else { Write-Host "[失败] $failure" -ForegroundColor Red; $failures.Add($failure) }
}

function Get-GyCoreVersionFromPath([string]$Path) {
  if ($Path -match '\\tsf-(\d+\.\d+\.\d+)\\GyIme\.dll$') { return $matches[1] }
  return ''
}

try {
  $gy = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\GYInput' -ErrorAction Stop
  $hostPath = [string]$gy.HostPath
  $hostVersion = [string]$gy.HostVersion
  # Host lives in <install>\versions\<version>; installation state lives at <install>.
  $statePath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $hostPath))) 'install-state.json'
  $state = if (Test-Path -LiteralPath $statePath) { Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } else { $null }
  $coreVersion = if ($state) { [string]$state.coreVersion } else { '' }
  $installRoot = Split-Path -Parent $statePath
  $pendingPath = Join-Path $installRoot 'pending-activation.json'
  $pendingErrorPath = Join-Path $installRoot 'pending-activation.error.log'
  Check ($state -and $state.activationState -eq 'active') '安装状态已确认 active。' '安装状态仍处于 pending/rollback 或缺少 active 标记。'
  Check ($state -and $state.registryVerified -eq $true) '安装状态包含注册表校验标记。' '安装状态缺少注册表校验标记。'
  Check ((-not (Test-Path -LiteralPath $pendingPath)) -and (-not (Test-Path -LiteralPath $pendingErrorPath))) '没有待激活或激活错误文件。' '仍存在待激活/激活错误文件，请先完成重启或回滚。'
  if ($state -and $state.requiresClientReload -eq $true) {
    Write-Host '[提示] 新版 TSF 核心已注册，但已打开的应用可能仍加载旧 DLL。请关闭并重新打开正在输入的应用；若仍显示旧版本，再重启 Windows。' -ForegroundColor Yellow
  }
  Check (-not [string]::IsNullOrWhiteSpace($coreVersion)) "当前核心版本：$coreVersion" '没有找到当前核心版本状态。'
  Check ($hostVersion -eq $coreVersion) "Host / 核心版本一致：$hostVersion" "Host / 核心版本不一致：Host=$hostVersion，Core=$coreVersion。请重新安装同一版本。"
  Check (-not [string]::IsNullOrWhiteSpace($hostVersion)) "当前 Host 版本：$hostVersion" '没有找到当前 Host 版本注册。'
  Check (Test-Path -LiteralPath $hostPath -PathType Leaf) "当前 Host 文件存在：$hostPath" '当前 Host 文件不存在。'
  Check ($state -and [string]::Equals($hostPath, [string]$state.host, [StringComparison]::OrdinalIgnoreCase)) '注册表 Host 与安装状态一致。' '注册表 Host 与安装状态不一致。'

  if (Test-Path -LiteralPath $hostPath -PathType Leaf) {
    $supportsHealthCheck = $false
    try { $supportsHealthCheck = ([version]$hostVersion -ge [version]'0.8.7') } catch {}
    $healthPath = Join-Path (Split-Path -Parent $hostPath) ("GyImeHealth-" + $hostVersion + ".exe")
    if ($supportsHealthCheck) {
      Check (Test-Path -LiteralPath $healthPath -PathType Leaf) "独立离线自检程序存在：$healthPath" '独立离线自检程序不存在。'
      if (Test-Path -LiteralPath $healthPath -PathType Leaf) {
        $process = Start-Process -FilePath $healthPath -WorkingDirectory (Split-Path -Parent $healthPath) -PassThru -Wait
        Check ($process.ExitCode -eq 0) '离线词库与拼音引擎健康检查通过。' "离线词库健康检查失败（退出码：$($process.ExitCode)）。"
      }
    } else {
      Check $false '' '当前 Host 版本过旧，不支持独立离线引擎健康检查；请安装最新 GY 更新包。'
    }
  }
} catch {
  Check $false '' "无法读取 GY 安装注册信息：$($_.Exception.Message)"
}

try {
  $server = Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Classes\CLSID\{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}\InprocServer32' -Name '(default)' -ErrorAction Stop
  Check (Test-Path -LiteralPath $server -PathType Leaf) "TSF DLL 已注册：$server" 'TSF DLL 注册缺失或文件不存在。'
  Check ($state -and [string]::Equals([string]$server, [string]$state.dll, [StringComparison]::OrdinalIgnoreCase)) 'TSF DLL 与安装状态一致。' 'TSF DLL 与安装状态不一致。'
  $registeredCoreVersion = Get-GyCoreVersionFromPath $server
  Check ($registeredCoreVersion -eq $coreVersion) "注册表 TSF 版本与状态一致：$registeredCoreVersion" "注册表 TSF 版本不一致：TSF=$registeredCoreVersion，State=$coreVersion。"
  $hostLogo = Join-Path (Split-Path -Parent $hostPath) 'gy.ico'
  $tsfLogo = Join-Path (Split-Path -Parent $server) 'gy.ico'
  Check (Test-Path -LiteralPath $hostLogo -PathType Leaf) "Host Logo 存在：$hostLogo" 'Host Logo 缺失。'
  Check (Test-Path -LiteralPath $tsfLogo -PathType Leaf) "TSF Logo 存在：$tsfLogo" 'TSF Logo 缺失。'
} catch {
  Check $false '' 'TSF DLL 注册缺失。'
}

try {
  $tips = Get-WinUserLanguageList | ForEach-Object { $_.InputMethodTips }
  Check ($tips -contains $tipId) '当前 Windows 账户已添加 GY 输入法。' '当前 Windows 账户没有 GY 输入法键盘项。'
} catch {
  Check $false '' "无法读取当前账户的输入法列表：$($_.Exception.Message)"
}

if ($failures.Count -gt 0) {
  Write-Host "`nGY 安装验证未通过：$($failures.Count) 项。不会修改任何系统设置。" -ForegroundColor Yellow
  exit 1
}
Write-Host "`nGY 安装验证完成：注册、账户配置和离线引擎均正常。" -ForegroundColor Green
exit 0
