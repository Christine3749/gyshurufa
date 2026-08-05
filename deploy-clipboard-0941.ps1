# deploy-clipboard-0941.ps1
# 0.9.41 clipboard-page test deploy. Run as Administrator.
# Rollback: rename GyImeHost-0.9.41.exe.clipboard-bak back to GyImeHost-0.9.41.exe
$ErrorActionPreference = 'Stop'
$hostPath = (Get-ItemProperty 'HKLM:\SOFTWARE\GYInput').HostPath
if (-not $hostPath) { throw 'HKLM:\SOFTWARE\GYInput HostPath not found' }
$newExe = 'C:\Users\Ethan\Desktop\01-Projects\shurufa\gy输入法\native\build-trace\bin\Release\GyImeHost.exe'
if (-not (Test-Path $newExe)) { throw "new build not found: $newExe" }
$bakName = [IO.Path]::GetFileName($hostPath) + '.clipboard-bak'
$bak = Join-Path (Split-Path $hostPath) $bakName
Remove-Item $bak -Force -ErrorAction SilentlyContinue
Rename-Item -Path $hostPath -NewName $bakName
Copy-Item $newExe $hostPath -Force
Get-Process | Where-Object { $_.Name -like 'GyImeHost*' } | Stop-Process -Force
Write-Host "deployed -> $hostPath" -ForegroundColor Green
Write-Host "next keystroke starts the new Host automatically" -ForegroundColor Yellow
