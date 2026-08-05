# GY 输入法 trace 版回滚（恢复 build-release 正式版 DLL）
# 用法：在【管理员】PowerShell 里执行：
#   powershell -ExecutionPolicy Bypass -File "C:\Users\Ethan\Desktop\01-Projects\shurufa\revert-trace-0940.ps1"
$ErrorActionPreference = 'Stop'
$releaseDll = 'C:\Users\Ethan\Desktop\01-Projects\shurufa\gy输入法\native\build-release\bin\Release\GyIme.dll'
$dll = 'C:\Program Files\GYInput\tsf-0.9.40\GyIme.dll'

Get-Process | Where-Object { $_.Name -like 'GyImeHost*' } | Stop-Process -Force -ErrorAction SilentlyContinue

# Loaded DLLs cannot be deleted, only renamed; the current DLL may also be
# missing after an interrupted run, so guard both renames.
if (Test-Path "$dll.trace-bak") {
  $stamp = Get-Date -Format 'HHmmss'
  Rename-Item "$dll.trace-bak" "$dll.trace-bak.$stamp"
}
if (Test-Path $dll) {
  Rename-Item $dll "$dll.trace-bak"
}
Copy-Item $releaseDll $dll -Force

Get-Process | Where-Object { $_.Name -in 'SearchHost','StartMenuExperienceHost','TextInputHost','explorer' } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe -ErrorAction SilentlyContinue

Write-Host 'OK: 已恢复正式版 DLL（build-release 最新构建）。建议注销重登一次全部生效。' -ForegroundColor Green
