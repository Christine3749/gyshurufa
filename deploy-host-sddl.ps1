# deploy-host-sddl.ps1 — 部署带沙盒授权的新 Host（需要管理员 PowerShell）
# 修复：Win 搜索框（SearchHost 等打包进程）连不上管道导致候选窗不出现
$ErrorActionPreference = 'Stop'
$dstDir = "C:\Program Files\GYInput\versions\0.9.40"
$dst = Join-Path $dstDir "GyImeHost-0.9.40.exe"
$src = "C:\Users\Ethan\Desktop\01-Projects\shurufa\gy输入法\native\build-release\bin\Release\GyImeHost.exe"

if (-not (Test-Path $src)) { throw "source not found: $src" }

# 1. 停掉正在运行的 Host（下次按键会自动拉起新的）
Get-Process | Where-Object { $_.Name -like "GyImeHost*" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

# 2. 挪走旧文件（已映射的 exe 只能改名不能覆盖）
$stamp = Get-Date -Format "HHmmss"
if (Test-Path $dst) { Rename-Item $dst "GyImeHost-0.9.40.exe.old-$stamp" }

# 3. 放入新 Host
Copy-Item $src $dst -Force

# 4. 验证
$info = Get-Item $dst
"OK: deployed $($info.Length) bytes, LastWrite $($info.LastWriteTime)"
"下一步：按 Win 键，在搜索框输入 woshishui，候选窗应该出现"
