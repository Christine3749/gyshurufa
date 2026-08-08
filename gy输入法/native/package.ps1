param(
  [string]$Version,
  [ValidateSet('Release')][string]$Configuration = 'Release',
  [string]$OutputRoot = (Join-Path $PSScriptRoot 'release')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ReleaseManifest.psm1') -Force
$manifest = Get-GYReleaseManifest
$Version = Assert-GYReleaseVersion -Manifest $manifest -RequestedVersion $Version

$build = Join-Path $PSScriptRoot 'build-release'
cmake -S $PSScriptRoot -B $build -G 'Visual Studio 17 2022' -A x64 "-DGY_VERSION=$Version"
cmake --build $build --config $Configuration --target GyIme GyImeHost GyImeHealth
if ($LASTEXITCODE -ne 0) { throw 'Native release build failed.' }

$binaryRoot = Join-Path $build "bin\$Configuration"
$packageRoot = Join-Path $OutputRoot "GYInput-$Version"
if (Test-Path -LiteralPath $packageRoot) { throw "Package output already exists: $packageRoot" }
$payloadRoot = Join-Path $packageRoot 'payload'
New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $binaryRoot 'GyIme.dll') -Destination (Join-Path $payloadRoot "GyIme-$Version.dll")
Copy-Item -LiteralPath (Join-Path $binaryRoot 'GyImeHost.exe') -Destination (Join-Path $payloadRoot "GyImeHost-$Version.exe")
Copy-Item -LiteralPath (Join-Path $binaryRoot 'GyImeHealth.exe') -Destination (Join-Path $payloadRoot "GyImeHealth-$Version.exe")

Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer\assets\gy.ico') -Destination (Join-Path $payloadRoot 'gy.ico')

$workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$notesSource = Join-Path $workspaceRoot "release\notes\$Version.txt"
if (-not (Test-Path -LiteralPath $notesSource)) { throw "Release notes are missing: $notesSource" }
Copy-Item -LiteralPath $notesSource -Destination (Join-Path $payloadRoot 'release-notes.txt')
Copy-Item -LiteralPath (Join-Path $binaryRoot 'rime.dll') -Destination (Join-Path $payloadRoot 'rime.dll')
Copy-Item -LiteralPath (Join-Path $binaryRoot 'rime-data') -Destination (Join-Path $payloadRoot 'rime-data') -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer\Install-GYInput.ps1') -Destination (Join-Path $packageRoot 'Install-GYInput.ps1')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer\Validate-GYInput.ps1') -Destination (Join-Path $packageRoot 'Validate-GYInput.ps1')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer\Rollback-GYInput.ps1') -Destination (Join-Path $packageRoot 'Rollback-GYInput.ps1')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer\Repair-GYInput.ps1') -Destination (Join-Path $packageRoot 'Repair-GYInput.ps1')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer\Finalize-GYClientReload.ps1') -Destination (Join-Path $packageRoot 'Finalize-GYClientReload.ps1')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer\Prune-GYOldVersions.ps1') -Destination (Join-Path $packageRoot 'Prune-GYOldVersions.ps1')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer\Register-GYInputActivationTasks.ps1') -Destination (Join-Path $packageRoot 'Register-GYInputActivationTasks.ps1')
New-Item -ItemType Directory -Path (Join-Path $packageRoot 'LICENSES') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer/GYInputTransaction.ps1') -Destination (Join-Path $packageRoot 'GYInputTransaction.ps1')
Copy-Item -LiteralPath (Get-GYReleaseManifestPath) -Destination (Join-Path $packageRoot 'release.json')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'runtime\rime\LICENSE.librime.txt') -Destination (Join-Path $packageRoot 'LICENSES\librime-BSD-3-Clause.txt')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'runtime\rime\LICENSE.rime-data.txt') -Destination (Join-Path $packageRoot 'LICENSES\rime-data-license.txt')
Set-Content -LiteralPath (Join-Path $packageRoot 'VERSION') -Value $Version -NoNewline -Encoding utf8

$hashLines = Get-ChildItem -LiteralPath $payloadRoot -File -Recurse | ForEach-Object {
  $relative = $_.FullName.Substring($payloadRoot.Length + 1)
  "{0}  {1}" -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, $relative
}
Set-Content -LiteralPath (Join-Path $payloadRoot 'SHA256SUMS.txt') -Value $hashLines -Encoding utf8

$readme = @"
GY 输入法 $Version

推荐安装（标准 EXE）
1. 下载同一版本的 GYInputSetup-$Version.exe。
2. 双击运行，按提示授权管理员权限。
3. 完成后按 Win + Space，选择“GY 输入法（拼音）”。

ZIP 是离线/高级用户备用包
1. 解压此 ZIP。
2. 在解压目录右键 Install-GYInput.ps1，选择“使用 PowerShell 运行”。
3. 脚本先校验 SHA-256，再请求管理员权限完成系统注册。
4. 若某次已验证升级不适配你的环境，可运行 .\Rollback-GYInput.ps1 回退到上一版；脚本会先自检旧版引擎。
5. 若“更新”页提示版本不一致，可点击“修复并清理”：它会重新核验当前安装，并只清理旧版本和失效临时安装文件。

长期更新架构
- TSF DLL 保持为小型 Windows 兼容层；词库、拼音算法和排序在本机 GyImeHost 进程运行。
- 0.6.x 使用安全的 sessionId 候选选择连接器；已安装 0.6.x 的用户更新 Host 不需要注销。
- 安装器会先运行独立的离线引擎自检程序；自检失败时保留旧 Host，不会切换到异常版本。
- 以后词库、拼音算法、排序和候选窗外观都由 Host 更新：下一次输入会使用新 Host，无需关闭应用或重启电脑。
- 仅从 0.5 或更早版本首次升级到 0.6.x 时需要注销一次；之后候选窗与交互更新只升级 Host，不会向其他应用注入按键。
- TSF DLL/核心连接器升级会先暂存新版本，重启 Windows 时自动激活并清理旧版本；Host、词库和候选窗更新不需要重启。

卸载：在 PowerShell 中运行 .\Install-GYInput.ps1 -Uninstall，或使用 Windows“已安装的应用”中的 GY 输入法。
本发行包完全离线运行，不上传输入内容。
"@
Set-Content -LiteralPath (Join-Path $packageRoot 'README.txt') -Value $readme -Encoding utf8
# Do not create the ZIP here. At this stage the installer/Mac hashes may still
# be pending. Finalize-GYRelease.ps1 is the sole owner of immutable ZIP output.
Write-Host "Release payload prepared: $packageRoot. Run Finalize-GYRelease.ps1 after both platform artifacts are verified."
