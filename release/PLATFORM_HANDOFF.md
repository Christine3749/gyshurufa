# GY Windows × macOS 共同机制

这是 Windows 与 Apple Silicon Mac 共同工作的唯一交接规则。两端共享产品行为和发布真相，**不共享系统底层代码**。

## 共享内容

| 共同部分 | 唯一来源 | 两端要求 |
| --- | --- | --- |
| 产品行为 | `GY_INPUT_METHOD_PRODUCT_STANDARD.md` | 简体／繁体／EN、离线输入、候选质量、5×5 及键盘规则一致；展开网格中方向键移动，`Enter` / `Space` 提交高亮候选。 |
| 已确认 VI | `gy输入法/GY_VISUAL_IDENTITY.md` | GY Logo、箭头、候选窗、颜色和设置页不得擅改。 |
| 发布真相 | `release/release.json` | 一个版本号、一个 Windows EXE、一个 Mac ARM64 PKG、各自 SHA-256。 |
| 发布校验 | `release/verify-release-manifest.mjs` | 先校验，再上传；只有双端完整才可以切换 `latest.json`。 |
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
2. 发布负责人在 `release/release.json` 创建一个新的、从未发布过的版本；`version`、`coreVersion`、`hostVersion` 必须相等。
3. Windows 构建 DLL、Host、EXE，执行原生测试与安装包验证；不得改动 `latest.json`。
4. Mac 用同一提交和同一版本构建 ARM64 PKG，Developer ID 签名、公证、staple、哈希复核后，只更新 canonical manifest 的 macOS 字段。
5. 两端都运行共享发布校验，再由 Windows 发布机最后切换 R2 的 `releases/latest.json`。
6. 官网只请求 `/api/releases/latest`；只有 Worker 返回已验证的 Windows 和 macOS 元数据时显示下载按钮。

## 当前 0.9.35 的真实状态

Windows `0.9.35` 是已本地验证的候选包：DLL、Host、安装包均为 `0.9.35`，10 项原生测试通过，实际 EXE 的 SHA-256 已写入 `release.json`。它尚未推送为线上正式 latest。

macOS 仍为 `verification-required`：尚未在 M1 实机完成同版本 ARM64 PKG 的签名、公证、staple 与哈希校验。因此本版本不能成为跨平台 `latest`，官网也不得把 Mac 标为“可下载”。
## GitHub 共同仓库

本地仓库当前没有配置 `origin`。得到正确 GitHub URL 后，仅执行一次：

```powershell
git remote add origin <你的-GitHub-仓库-URL>
git push -u origin main
```

Mac 和 Windows 都只从该仓库同步；每次工作前拉取，完成后走独立提交。不要用压缩包、U 盘副本或“同版本覆盖”来同步源码或发布物。
