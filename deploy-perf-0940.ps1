# GY 输入法性能优化版本地部署（补丁式，仍是 0.9.40，协议未变）
# 用法：在【管理员】PowerShell 里执行：
#   powershell -ExecutionPolicy Bypass -File "C:\Users\Ethan\Desktop\01-Projects\shurufa\deploy-perf-0940.ps1"
$ErrorActionPreference = 'Stop'
$src = 'C:\Users\Ethan\Desktop\01-Projects\shurufa\gy输入法\native\build-release\bin\Release'
$hostExe = 'C:\Program Files\GYInput\versions\0.9.40\GyImeHost-0.9.40.exe'
$dll = 'C:\Program Files\GYInput\tsf-0.9.40\GyIme.dll'

Get-Process | Where-Object { $_.Name -like 'GyImeHost*' } | Stop-Process -Force -ErrorAction SilentlyContinue

Remove-Item "$hostExe.old", "$dll.old" -Force -ErrorAction SilentlyContinue
Rename-Item $hostExe "$hostExe.old"
Copy-Item "$src\GyImeHost.exe" $hostExe -Force
Rename-Item $dll "$dll.old"
Copy-Item "$src\GyIme.dll" $dll -Force

Write-Host 'OK: 新 Host + 新 DLL 已就位（旧文件保留为 .old 可回滚）' -ForegroundColor Green
Write-Host '注意：DLL 侧的优化（TTL/异步学习）在每个 App 重启后生效；想全部生效可注销重登一次。' -ForegroundColor Yellow
