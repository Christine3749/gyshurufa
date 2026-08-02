[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$tipId = '0804:{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}{5F689D3E-73E3-4C2B-979A-2DD86E438D6F}'
$failures = [System.Collections.Generic.List[string]]::new()

function Check([bool]$condition, [string]$success, [string]$failure) {
  if ($condition) { Write-Host "[通过] $success" -ForegroundColor Green }
  else { Write-Host "[失败] $failure" -ForegroundColor Red; $failures.Add($failure) }
}

try {
  $gy = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\GYInput' -ErrorAction Stop
  $hostPath = [string]$gy.HostPath
  $hostVersion = [string]$gy.HostVersion
  # Host lives in <install>\versions\<version>; installation state lives at <install>.
  $statePath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $hostPath))) 'install-state.json'
  $state = if (Test-Path -LiteralPath $statePath) { Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } else { $null }
  $coreVersion = if ($state) { [string]$state.coreVersion } else { '' }
  Check (-not [string]::IsNullOrWhiteSpace($coreVersion)) "当前核心版本：$coreVersion" '没有找到当前核心版本状态。'
  Check ($hostVersion -eq $coreVersion) "Host / 核心版本一致：$hostVersion" "Host / 核心版本不一致：Host=$hostVersion，Core=$coreVersion。请重新安装同一版本。"
  Check (-not [string]::IsNullOrWhiteSpace($hostVersion)) "当前 Host 版本：$hostVersion" '没有找到当前 Host 版本注册。'
  Check (Test-Path -LiteralPath $hostPath -PathType Leaf) "当前 Host 文件存在：$hostPath" '当前 Host 文件不存在。'

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
  $server = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Classes\CLSID\{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}\InprocServer32' -ErrorAction Stop).'(default)'
  Check (Test-Path -LiteralPath $server -PathType Leaf) "TSF DLL 已注册：$server" 'TSF DLL 注册缺失或文件不存在。'
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