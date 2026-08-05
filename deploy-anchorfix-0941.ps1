# deploy-anchorfix-0941.ps1
# Deploys: settings clipboard list page (Host) + candidate anchor clamp (DLL).
# Run as Administrator. After deploy: restart Kimi (or sign out/in) so the new
# DLL loads; the IME DLL cannot unload from running processes.
$ErrorActionPreference = 'Stop'
$buildDir = 'C:\Users\Ethan\Desktop\01-Projects\shurufa\gy输入法\native\build-trace\bin\Release'
$hostPath = (Get-ItemProperty 'HKLM:\SOFTWARE\GYInput').HostPath
if (-not $hostPath) { throw 'HKLM:\SOFTWARE\GYInput HostPath not found' }
$versionDir = Split-Path $hostPath                       # ...\versions\0.9.41
$version = Split-Path $versionDir -Leaf                  # 0.9.41
$dllPath = Join-Path (Split-Path $versionDir -Parent | Split-Path -Parent) "tsf-$version\GyIme.dll"
if (-not (Test-Path $dllPath)) { throw "installed DLL not found: $dllPath" }

# 1. Host exe (rename unlocks the running file, then copy)
$hostBak = "$hostPath.anchor-bak"
Remove-Item $hostBak -Force -ErrorAction SilentlyContinue
Rename-Item -Path $hostPath -NewName (Split-Path $hostBak -Leaf)
Copy-Item "$buildDir\GyImeHost.exe" $hostPath -Force
Get-Process | Where-Object { $_.Name -like 'GyImeHost*' } | Stop-Process -Force

# 2. TSF DLL (rename works even while loaded in apps)
$dllBak = "$dllPath.anchor-bak"
Remove-Item $dllBak -Force -ErrorAction SilentlyContinue
Rename-Item -Path $dllPath -NewName (Split-Path $dllBak -Leaf)
Copy-Item "$buildDir\GyIme.dll" $dllPath -Force

Write-Host "deployed Host + DLL ($version)" -ForegroundColor Green
Write-Host "restart Kimi (or sign out/in) to load the new DLL, then retest: type in PowerShell, Enter, back to Kimi, type wo" -ForegroundColor Yellow
