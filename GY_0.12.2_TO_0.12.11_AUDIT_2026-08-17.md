# GY 0.12.2 → 0.12.11 源码与发布证据审计

审计日期：2026-08-17（Asia/Shanghai）  
审计分支：`codex/gy-0.12.11-runtime-host-supervision`  
报告生成前 HEAD：`4854ef8f7ad70281ff4de92f085e2589dd277d1f`

## 1. 结论与证据边界

Ethan 指定 0.12.2 为稳定使用基线。本报告按该产品基线比较后续代码，但保留发布元数据的原始事实：R2 内的 0.12.2 `release.json` 将其标记为 `channel=candidate`、`state=candidate`。

0.12.2 的公开不可变 EXE 和 ZIP 仍可从 R2 完整回读；其中包含版本化运行文件、安装脚本、词库和 `release.json`，但不包含 C++ 源码，也不记录 `sourceCommit`。

Git 历史中也没有 0.12.2 标签、0.12.2 分支或 0.12.2 GitHub Actions 构建记录。0.12.0～0.12.5 的源码及发布说明是在提交 `71bdfdfbf6fbd2fc9a20609786d10554e10e4c55` 中一次性快照进入 Git 的；该提交相对父提交一次改变 123 个文件（29,711 行增加、1,154 行删除），已经混合 0.12.2、0.12.3、0.12.4 和 0.12.5 的状态。

因此：

- 0.12.2 发布包内的 PowerShell 安装代码和二进制可做精确比较；
- 0.12.2 C++ 源码不能从现存证据中无损还原，禁止伪造逐行差异；
- 后续可复现的完整源码比较以 0.12.5 固定快照 `71bdfdf` 为 Git 基线；
- `71bdfdf..4854ef8` 共 25 个提交、43 个文件、1,552 行增加、171 行删除。

## 2. 0.12.2 R2 发布包证据

版本固定地址：

- EXE：`https://download.shurufa.wang/download/candidate/windows/0.12.2`
- ZIP：`https://download.shurufa.wang/download/candidate/windows/0.12.2/zip`

完整回读结果：

| 对象 | 字节数 | SHA-256 / 版本 |
|---|---:|---|
| `GYInputSetup-0.12.2.exe` | 10,275,953 | `2E8579D2B30D7261EFD3CB32779F14CD4F4B43F1DE1D12940CA9118B8C8FCFD6`；ProductVersion `0.12.2` |
| `GYInput-0.12.2.zip` | 11,604,921 | `D5662540E9F8D9AAA4E983BCC185EE7997849BB1F33B334A8B7DC6DD84E44A2A` |
| `GyIme-0.12.2.dll` | 269,824 | `9BFE40433B1D211F1CFCBD5DF51A4636FC30071A462093A7CD78888C72A7274F` |
| `GyImeHost-0.12.2.exe` | 666,624 | `52D2F07B0A9C5D3BFD77666F54FBE1D0BF96A69B972D2E83F4E7F0830D39766F` |
| `GyImeHealth-0.12.2.exe` | 335,360 | `716405B0B577D69EDD760D6250E58AFDFEF21A1D6CAC981F22DA80175FF5104A` |
| `rime.dll` | 2,885,632 | `7567D9403103AEBEA9717032E113E32EC1E0DF2AE13AE0BF00E3753BDA37B684` |

0.12.2 `release.json` 的关键身份为：

- `releaseId=gy-2026.08.13-windows-0.12.2-thinkpad-test`
- `version=coreVersion=hostVersion=0.12.2`
- `architecture=x64`
- `signed=false`
- `realApplications=pending`
- `pointerPolicy=version-pinned-only`

## 3. 0.12.2 打包脚本与当前源码的精确比较

忽略 CRLF/LF 和文件编码造成的非逻辑差异后，0.12.2 ZIP 中 14 个 PowerShell 脚本与当前源码比较如下。

逻辑内容相同（7 个）：

- `AutoUpdate-GYInput.ps1`
- `Get-GYKeepHealth.ps1`
- `Get-GYLoadedClientState.ps1`
- `GYInputTransaction.ps1`
- `Migrate-GYLegacyInstallEntries.ps1`
- `Prune-GYOldVersions.ps1`
- `Sync-GYEnglishLexicon.ps1`

逻辑内容已变更（7 个）：

| 文件 | 增加 | 删除 | 主要目的 |
|---|---:|---:|---|
| `Finalize-GYClientReload.ps1` | 2 | 2 | 延迟激活和版本切换校验 |
| `Install-GYInput.ps1` | 33 | 5 | 版本化 TSF/Host、恢复和激活事务 |
| `Register-GYInputActivationTasks.ps1` | 18 | 11 | ONSTART + ONLOGON 冗余、BootId 门控 |
| `Repair-GYInput.ps1` | 18 | 0 | 修复时恢复 Host/核心一致性 |
| `Rollback-GYInput.ps1` | 15 | 0 | 回滚后恢复注册与当前版本 Host |
| `Set-GYKeyboard.ps1` | 126 | 8 | 账户语言列表、TIP 和 Host 协调 |
| `Validate-GYInput.ps1` | 38 | 0 | 增加版本、注册、Host、DLL 和旧客户端验证 |

当前包比 0.12.2 新增 `Recover-GYIncompleteRegistration.ps1`。0.12.11 包不再携带 0.12.2 ZIP 中一批未选用的 Rime 源 YAML/README/Makefile，只携带实际部署和验证所需的运行数据。

## 4. 0.12.11 构建绑定

0.12.11 的候选二进制由源码提交 `0c6506b018dfcdf4fe85646f82fd4956020c9c55` 构建，分支为 `codex/gy-0.12.11-runtime-host-supervision`，CI 运行 `31939189786`。

| 对象 | 字节数 | SHA-256 |
|---|---:|---|
| `GyIme.dll` | 322,560 | `428676C1494920F17D0B673982F1A12E15D77D5D100C731FF9450409425FA4D4` |
| `GyImeHost.exe` | 679,936 | `EC46F02AE97E71C0256830F8FEFF9522653DA172178A76512EA09DC9D53EC8AD` |
| `GyImeHealth.exe` | 335,360 | `EE1E9FBC4C8185F62AF52BE970BC87C16AD6D3DE898C116B4449EDBDDF7AFE29` |
| `GYInputSetup-0.12.11.exe` | 7,988,269 | `2FA7CC1BB4D6493A5BEB33AAD073697FB755ED7BF1AAF1D44BBA186159EE1F4D` |
| `GYInput-0.12.11.zip` | 8,499,758 | `55C939392B8EAD3BF09517C75E29F3FBB3BB5FB128C3A7D3E38EA9C787BCB11E` |

构建后还有三个只影响分发基础设施、不改变 0.12.11 安装包哈希的提交：R2 Range 支持、R2 自定义下载域名、旧 Vercel 下载地址跳转。

## 5. 可复现的完整源码过程：0.12.5 固定快照 → 当前分支

以下 25 个提交均属于当前非默认分支的祖先链：

1. `e6b9888` — `diag(tsf): trace Firefox address bar lifecycle for 0.12.6`
2. `dc6a374` — `ci: preserve dotted candidate version in PowerShell`
3. `621bfdc` — `ci: separate environment-bound Windows checks`
4. `466f12e` — `ci: isolate mutable Rime learning smoke`
5. `434d3bb` — `release: use canonical pending hash for 0.12.6 draft`
6. `449b229` — `fix(ime): reject mixed-version candidate hosts`
7. `59e5fda` — `release: bind 0.12.6 candidate evidence [skip ci]`
8. `d1c8fa0` — `release: withdraw 0.12.6 and start 0.12.7`
9. `cb4307b` — `release: burn 0.12.6 and prepare 0.12.7`
10. `5bed65f` — `release: bind first 0.12.7 candidate hash [skip ci]`
11. `8a29125` — `fix(installer): recover verified missing host metadata for 0.12.8`
12. `322ba27` — `release: bind first 0.12.8 candidate hash [skip ci]`
13. `1a900e3` — `fix(installer): move recovery helper out of temp for 0.12.9`
14. `b6c7d90` — `release: bind first 0.12.9 candidate hash [skip ci]`
15. `b89b3bf` — `fix(installer): reconcile versioned host startup for 0.12.10`
16. `b35cdd0` — `release: bind first 0.12.10 candidate hash [skip ci]`
17. `3f695b7` — `release: record 0.12.10 target-test approval [skip ci]`
18. `9621dae` — `fix(runtime): add redundant activation and host recovery for 0.12.11`
19. `bea8c86` — `test(runtime): allow isolated host handoff on elevated CI`
20. `0c6506b` — `fix(runtime): restart an unavailable registered host immediately`
21. `2f15edd` — `release: bind first 0.12.11 candidate hash [skip ci]`
22. `e9f6dd8` — `release: approve 0.12.11 target-test distribution [skip ci]`
23. `c3fa5c8` — `Fix R2 byte-range downloads`
24. `9cc55c4` — `Route release downloads through R2 custom domain`
25. `4854ef8` — `Redirect legacy downloads to R2 edge`

主要代码变化：

- TSF：加入不记录输入文本的 Firefox 生命周期、Context、EditSession、InputScope 和 mode-generation 追踪；修复直接输入域切换、组合清理和异步编辑会话边界。
- Host：拒绝混合版本 Host；加入已注册版本的一次性协调器、私有 Status/Shutdown 协议、互斥锁和失联 Host 立即恢复。
- 安装：从单一延迟任务升级为 BootId 门控的 ONSTART + ONLOGON 冗余激活；加入缺失元数据恢复、版本化 DLL/Host 校验、回滚和旧客户端检测。
- 测试/CI：增加真实 Windows 环境边界、隔离 Rime 学习状态、旧 Host 交接与重新启动测试；候选哈希与源码提交绑定。
- 分发：安装包继续保持不可变；下载切换为 Cloudflare Worker + R2，自定义域支持 `206 Partial Content` 和断点续传；旧 Vercel 下载地址只做 307 跳转。

## 6. 版本处置状态

- 0.12.6、0.12.7、0.12.8、0.12.9、0.12.10 已永久撤回/烧毁，不得覆盖重建或重新进入发布链路。
- 0.12.11 安装包不可变，当前仍是 ThinkPad 目标测试候选；真实 Firefox、Windows Search、简繁模式及跨应用验收结果不能由静态测试代替。
- 若 0.12.11 重启后的真实测试失败，下一候选必须提升为 0.12.12。

## 7. 复现命令

```powershell
git log --reverse --oneline 71bdfdfbf6fbd2fc9a20609786d10554e10e4c55..4854ef8f7ad70281ff4de92f085e2589dd277d1f
git diff --stat 71bdfdfbf6fbd2fc9a20609786d10554e10e4c55..4854ef8f7ad70281ff4de92f085e2589dd277d1f
git diff 71bdfdfbf6fbd2fc9a20609786d10554e10e4c55..4854ef8f7ad70281ff4de92f085e2589dd277d1f
```

这些命令只比较固定源码对象，不依赖默认分支，也不会改变稳定版通道。
