# GY 输入法发布流程

## 交付物

每个版本发布两种安装方式：

- `GYInputSetup-<version>.exe`：面向普通用户的标准安装包，优先分发。
- `GYInput-<version>.zip`：离线与高级用户备用包，包含完整性清单和 PowerShell 安装器。

两种方式都提供 64 位 TSF 兼容 DLL、GyImeHost 离线引擎进程和 Rime 词库；用户不需要安装 CMake、Visual Studio 或 Rime。

## 构建

在项目根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\native\package.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\native\build-installer.ps1
```

安装器采用版本并存目录：`C:\Program Files\GYInput\versions\<version>`。升级会注册新版本 DLL，而不会覆盖已被微信、Chrome、ChatGPT、Office 等进程加载的旧 DLL。首次升级到 Host 架构时，已打开的应用关闭后重新打开一次即可使用新兼容层；以后仅词库/算法 Host 更新会在下一次输入时自动切换，无需重启电脑或关闭应用。

## 安装、修复与卸载

标准 EXE 会自动：验证 64 位环境、复制完整离线运行时、注册系统文本服务，并将 GY 加入当前账户的中文键盘列表。相同版本再次运行时提供“修复键盘列表/重新注册”而不是覆盖文件。

卸载时，仅当当前版本仍是系统激活版本才会注销它，避免旧安装器误伤后续版本。被已打开应用占用的旧版本不会被强制删除。

## 发布前检查

- 在已安装旧版且 Chrome、微信等应用保持打开的系统上测试升级。
- 在新的 Windows 用户账户测试首次安装、修复和卸载。
- 生成并发布 EXE 和 ZIP 的 SHA-256 文件。
- 使用 Authenticode 证书签名 DLL 与 EXE；未签名版本仍会触发 Windows 发布者警告。