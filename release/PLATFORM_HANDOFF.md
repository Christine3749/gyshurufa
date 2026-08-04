# GY Windows × macOS 共同机制

这是 Windows 与 Apple Silicon Mac 共同工作的唯一交接规则。两端共享产品行为和发布真相，**不共享系统底层代码**。

## 共享内容

| 共同部分 | 唯一来源 | 两端要求 |
| --- | --- | --- |
| 产品行为 | `GY_INPUT_METHOD_PRODUCT_STANDARD.md` | 简体／繁体／EN、离线输入、候选质量、5×5 及键盘规则一致；展开网格中方向键移动，`Enter` / `Space` 提交高亮候选。 |
| 已确认 VI | `gy输入法/GY_VISUAL_IDENTITY.md` | GY Logo、箭头、候选窗、颜色和设置页不得擅改。 |
| 发布真相 | `release/release.json` | Windows 与 Mac 各有独立版本号、文件和 SHA-256；共享同一个清单格式，不共享版本号。 |
| 发布校验 | `release/verify-release-manifest.mjs` | 先校验，再上传；每个平台只能切换自己的 `latest`。 |
| 账户与同步契约 | `release/ACCOUNT_CONTRACT.md` | 两端同一 GY 账户；令牌分别放 DPAPI / Keychain。 |

## 不共享的部分

| Windows | macOS |
| --- | --- |
| TSF DLL、Host、注册表、Inno Setup、命名管道 | InputMethodKit、Input Source、Keychain、Developer ID、notarization |
| x64 EXE | Apple Silicon arm64 PKG |
| 关闭/重新打开输入应用以激活 DLL | 退出使用输入法的应用/必要时注销以激活 Bundle |

**禁止**把 Windows DLL/Host 的实现移植进 Mac，也禁止把 macOS Bundle/PKG 的安装逻辑带回 Windows。

## 每次发布的交接顺序

1. Windows 和 Mac 都先执行 `git pull --ff-only origin main`。
2. 发布负责人在 `release/release.json` 创建一个新的、从未发布过的平台版本；Windows 的 `version`、`coreVersion`、`hostVersion` 必须相等，macOS 版本独立管理。
3. Windows 构建 DLL、Host、EXE，执行原生测试与安装包验证；不得改动 `latest.json`。
4. Mac 用同一提交构建 ARM64 PKG，Developer ID 签名、公证、staple、哈希复核后，只更新 canonical manifest 的 macOS 字段；其版本不必等于 Windows。
5. 两端都运行共享发布校验；Windows 发布机只切换 Windows `latest`，Mac 发布机只切换 macOS `latest`。
6. 官网只请求 `/api/releases/latest`；Worker 对每个平台单独返回已验证状态，只有该平台验证完成才显示该平台下载按钮。

## 当前状态说明

当前候选版本必须以 `release/release.json` 为准。Windows 和 macOS 分别验证、分别发布、分别回滚；任何一端未完成签名或验证时，只隐藏该端下载，不影响另一端已经验证的版本。
## GitHub 共同仓库

本地仓库当前没有配置 `origin`。得到正确 GitHub URL 后，仅执行一次：

```powershell
git remote add origin <你的-GitHub-仓库-URL>
git push -u origin main
```

Mac 和 Windows 都只从该仓库同步；每次工作前拉取，完成后走独立提交。不要用压缩包、U 盘副本或“同版本覆盖”来同步源码或发布物。
