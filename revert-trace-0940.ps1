# GY 输入法 trace 版回滚（恢复正式 DLL）
# 用法：在【管理员】PowerShell 里执行：
#   powershell -ExecutionPolicy Bypass -File "C:\Users\Ethan\Desktop\01-Projects\shurufa\revert-trace-0940.ps1"
$ErrorActionPreference = 'Stop'
$dll = 'C:\Program Files\GYInput\tsf-0.9.40\GyIme.dll'

Get-Process | Where-Object { $_.Name -like 'GyImeHost*' } | Stop-Process -Force -ErrorAction SilentlyContinue

Remove-Item $dll -Force -ErrorAction SilentlyContinue
Rename-Item "$dll.trace-bak" $dll

Get-Process | Where-Object { $_.Name -in 'SearchHost','StartMenuExperienceHost','TextInputHost','explorer' } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe -ErrorAction SilentlyContinue

Write-Host 'OK: 已恢复正式 DLL。' -ForegroundColor Green
