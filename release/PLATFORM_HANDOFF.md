# GY Windows × macOS 共同机制

这是 Windows 与 Apple Silicon Mac 共同工作的唯一交接规则。两端共享产品行为和发布真相，**不共享系统底层代码**。

## 共享内容

| 共同部分 | 唯一来源 | 两端要求 |
| --- | --- | --- |
| 产品行为 | `GY_INPUT_METHOD_PRODUCT_STANDARD.md` | 简体／繁体／EN、离线输入、候选质量、5×5 及键盘规则一致。 |
| 已确认 VI | `gy输入法/GY_VISUAL_IDENTITY.md` | GY Logo、箭头、候选窗、颜色和设置页不得擅改。 |
| 发布真相 | `release/release.json` | 一个版本号、一个 Windows EXE、一个 Mac ARM64 PKG、各自 SHA-256。 |
| 发布校验 | `release/verify-release-manifest.mjs` | 先校验，再上传；只有双端完整才可以切换 `latest.json`。 |
| 账户与同步契约 | `release/ACCOUNT_CONTRACT.md` | 两端同一 GY 账户；令牌分别放 DPAPI / Keychain。 |
| 韧性架构与更新 | `release/ARCHITECTURE_CONTRACT.md` | 稳定 Bridge、Session Guard、双完整 Engine、独立 Panel 与 Account Agent；输入路径零网络。 |

## 不共享的部分

| Windows | macOS |
| --- | --- |
| TSF DLL、Engine/Agent、注册表、Inno Setup、命名管道 | InputMethodKit Bridge、Engine/Agent、Keychain、Developer ID、notarization |
| x64 EXE | Apple Silicon arm64 PKG |
| 关闭/重新打开输入应用以激活 DLL | 退出使用输入法的应用/必要时注销以激活 Bundle |

**禁止**把 Windows DLL/Host 的实现移植进 Mac，也禁止把 macOS Bundle/PKG 的安装逻辑带回 Windows。

## 每次发布的交接顺序

1. Windows 和 Mac 都先执行 `git pull --ff-only origin main`。
2. 发布负责人在 `release/release.json` 创建一个新的、从未发布过的版本；`version`、`coreVersion`、`hostVersion` 必须相等。
3. Windows 构建 DLL、Host、EXE，执行原生测试与安装包验证；不得改动 `latest.json`。
4. Mac 用同一提交和同一版本构建 ARM64 PKG，Developer ID 签名、公证、staple、哈希复核后，只更新 canonical manifest 的 macOS 字段。
5. 两端都运行共享发布校验，再由 Windows 发布机最后切换 R2 的 `releases/latest.json`。
6. 官网只请求 `/api/releases/latest`；只有 Worker 返回已验证的 Windows 和 macOS 元数据时显示下载按钮。

## 当前发布状态

以 `release/release.json` 为准。候选构建、未签名 Windows 包或未公证的 Mac PKG 都不能成为跨平台 `latest`，也不应被官网标为“正式可下载”。

## GitHub 共同仓库

Mac 和 Windows 都只从配置好的 GitHub 仓库同步；每次工作前拉取，完成后走独立提交。不要用压缩包、U 盘副本或“同版本覆盖”来同步源码或发布物。
