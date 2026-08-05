# GY 输入法 trace 诊断版部署（含 P0: TF_IAS_QUERYONLY 修复）
# 用法：在【管理员】PowerShell 里执行：
#   powershell -ExecutionPolicy Bypass -File "C:\Users\Ethan\Desktop\01-Projects\shurufa\deploy-trace-0940.ps1"
$ErrorActionPreference = 'Stop'
$traceDll = 'C:\Users\Ethan\Desktop\01-Projects\shurufa\gy输入法\native\build-trace\bin\Release\GyIme.dll'
$dll = 'C:\Program Files\GYInput\tsf-0.9.40\GyIme.dll'

Get-Process | Where-Object { $_.Name -like 'GyImeHost*' } | Stop-Process -Force -ErrorAction SilentlyContinue

# A loaded DLL can be renamed but not deleted: move any previous backup
# aside with a unique name, then move the current DLL aside if present.
# (The current DLL may legitimately be missing after an interrupted run.)
if (Test-Path "$dll.trace-bak") {
  $stamp = Get-Date -Format 'HHmmss'
  Rename-Item "$dll.trace-bak" "$dll.trace-bak.$stamp"
}
if (Test-Path $dll) {
  Rename-Item $dll "$dll.trace-bak"
}
Copy-Item $traceDll $dll -Force

# 让这些进程立刻重载新 DLL（它们各自自动重启，不用注销）
Get-Process | Where-Object { $_.Name -in 'SearchHost','StartMenuExperienceHost','TextInputHost','explorer' } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe -ErrorAction SilentlyContinue

Remove-Item "$env:TEMP\GyIme.trace.log" -Force -ErrorAction SilentlyContinue

Write-Host 'OK: trace 版 DLL 已就位，日志将写入 %TEMP%\GyIme.trace.log' -ForegroundColor Green
Write-Host '下一步：注销重登一次，然后 Win 键搜索框慢速输入 woshishui 观察光标' -ForegroundColor Yellow
Write-Host '回滚：powershell -ExecutionPolicy Bypass -File "C:\Users\Ethan\Desktop\01-Projects\shurufa\revert-trace-0940.ps1"' -ForegroundColor Yellow
