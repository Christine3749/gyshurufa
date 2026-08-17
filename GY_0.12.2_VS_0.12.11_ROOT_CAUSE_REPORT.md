# GY 0.12.2 与 0.12.11 根因对比审计

> 状态：**审计草案，尚未签署最终测试结论**
> 审计日期：2026-08-17（Asia/Shanghai）
> 审计分支：`codex/gy-0.12.2-vs-0.12.11-root-cause-audit`
> 冻结约束：本审计没有修改 GY 源码，没有生成 0.12.12，没有打包、部署 R2 或更新 shurufa.wang。

## 1. 结论摘要

1. **0.12.2 二进制可验证，但源码不可验证。** 可信 DLL 的大小与 SHA-256 完全匹配用户给定基线；公开安装包、ZIP、Host 和 Health 也已取得并计算哈希。然而公开 `release.json` 没有 `sourceCommit`，仓库没有 0.12.2 标签、分支、Actions 源产物或能够与该 DLL 建立哈希关系的提交。因此本报告必须明确写：**0.12.2 缺少可验证源码**。后来的 0.12.5 源码不得冒充 0.12.2。
2. **0.12.11 的源码—CI—二进制—安装文件链可以闭合。** 候选包由提交 `0c6506b018dfcdf4fe85646f82fd4956020c9c55` 的成功 CI 运行 `31939189786` 产生；机器上安装的三个 0.12.11 文件与 CI 产物逐字节哈希一致。
3. **重启前“选中 GY 但没有中文候选”的直接根因已经确认，不是简繁体策略。** 当时注册表和 `install-state.json` 已激活 0.12.11，但 Firefox、Chrome、Explorer、Windows Search 和 Codex/ChatGPT 进程仍实际加载 0.12.10 DLL。0.12.10 DLL 按编译时版本拒绝使用注册为 0.12.11 的 Host，所以候选引擎失败关闭，表现为只能输出英文/原始字母。正常重启后这些进程已经全部加载 0.12.11；重启后的新故障不能继续用混载解释。
4. **该混载由 0.12.11 的延迟激活时序放大。** 本机在 2026-08-16 20:39:51 启动，Explorer 等客户端在 20:40:06—20:40:32 已加载 0.12.10；0.12.11 到次日 08:42:45 才由完成器切换注册表。提交 `9621daed7c2598d42e2ec6f3769df4405855e1e8` 首次加入延迟 20 秒的 ONSTART/ONLOGON 冗余激活路径。BootId 只能证明“已经跨过一次启动”，不能证明“当前登录会话里的 TSF 客户端尚未启动”，所以晚到的 ONLOGON 会在活跃会话中切换注册表。
5. **Firefox 首字母问题的旧代码根因可从历史源码证明。** 在 `fb76cf402e8240a0d30b4d41d95bd72519b01c10` 中，`TF_S_ASYNC` 会被当成非 `S_OK`，组合对象会提前本地释放；所有异步动作又会被 mode generation 一刀切丢弃；URL scope 在 `OnEndEdit` 才出现时直接取消首字母；scope 读取还使用同步读锁。`71bdfdfbf6fbd2fc9a20609786d10554e10e4c55` 是仓库中首个可验证地同时修正这些路径的源码快照，但由于 0.12.2—0.12.5 的源码历史被压成一个大提交，**无法证明首次引入回归的提交**。
6. **当前真实 Firefox 生命周期日志显示修正后的异步路径能够成功完成一次地址栏首字母转换。** Firefox 在同一个 `ITfContext` 上先创建组合；`OnEndEdit` 识别 URL 后，`commit-raw-direct` 的 `RequestEditSession` 返回 `0x00040300`（`TF_S_ASYNC`）；组合对象保持到异步 `DoEditSession`，随后成功提交原始首字母并结束组合，下一字母走 direct pass。该证据来自本机实际加载的 **0.12.10 DLL**，不是 0.12.11 的二进制测试，也还不是“连续 20 个新标签页”的最终验收。
7. **纯 0.12.11 的 Firefox 地址栏仍有一个独立、已确认的策略错误。** 地址栏已被 TSF 与 Host 缓存共同识别为 direct URL 域（`scope_direct=1`），但 `ToggleEnglishMode()` 允许 Shift 设置 `input_scope_manual_override_`；随后 `EffectiveInputScopeDirect()` 返回 false，GY 继续吞掉地址栏字母、建立组合并显示中文候选。用户截图和无文本日志都直接证明该路径，首次可验证引入提交为 `38377d4cfd46ffdf4d9bc8b0c784293903a0b1b6`。这违反“Firefox/Chrome 地址栏永不显示中文候选”的验收标准。
8. **纯 0.12.11 的简体模式确实泄漏繁体，不是指示灯错误。** 正在运行的 0.12.11 Host 对 mode=0 查询 `houmian`、`weishenme`，分别返回首选 `後面`、`爲什麽`；mode=1 返回 `後面`、`爲什麼`。Schema 引用了 `t2s.json`，但安装目录没有 OpenCC 配置/词典；备用 `LCMapStringEx(LCMAP_SIMPLIFIED_CHINESE)` 在本机也原样返回 `後面`、`爲什麽`。因此某些字能转换（如 `誰→谁`、`臥→卧`），另一些字稳定漏出。
9. **纯 0.12.11 的 Windows Search 故障不是激活失败。** SearchHost 实际加载 0.12.11，TSF 激活、普通文本 InputScope、组合启动、两次 `SetText`、`SetSelection` 和异步编辑均返回成功；用户却观察到预期 `wu` 变为 `uw`。这把问题收敛到 XAML/CoreText TextStore 的组合范围/选择锚点语义：当前实现只检查 HRESULT，没有验证宿主在更新后保留的实际 range/selection 位置。切换日志同时证明 SearchHost 会进入 mode=2；“没有中文候选”和“字母倒序”必须分开修复。

## 2. 审计边界与证据等级

| 等级 | 含义 |
|---|---|
| 已确认 | 有哈希、注册表、进程模块、时间线、真实 TSF 日志或可执行代码路径直接支持 |
| 源码确认 | 源码与静态/CI 测试支持，但尚未在指定真实应用完成视觉和输入验收 |
| 待证明 | 当前证据不足，必须在版本身份闭合后进行人工真实应用测试 |
| 不可证明 | 缺少对应源码或连续提交历史，不能用推测补齐 |

本审计没有把设置页标题当作版本证据。版本身份以 Git、PE 版本资源、字节数、SHA-256、安装状态、注册表和进程实际加载模块共同确定。

## 3. 版本身份与哈希

### 3.1 0.12.2 基线

#### 源码身份

| 项目 | 结果 |
|---|---|
| Git 分支 | 未找到可验证的 0.12.2 分支 |
| 完整提交号 | 未找到 |
| 标签 | 未找到 0.12.2 标签 |
| Actions 源产物 | 未找到 |
| 发布清单 `sourceCommit` | 公开 `release.json` 未提供 |
| 审计结论 | **0.12.2 缺少可验证源码** |

仓库中字符串 `0.12.2` 首次出现在提交 `71bdfdfbf6fbd2fc9a20609786d10554e10e4c55` 所包含的交接材料中，但该提交本身已经把源码版本标为 0.12.5，其父提交 `fb76cf402e8240a0d30b4d41d95bd72519b01c10` 是 0.10.90。`71bdfdf` 一次改变 123 个文件（约 +29,711/-1,154），不能反向推导出可信 0.12.2 源码。

#### 公开二进制与发行物

| 文件 | PE 文件/产品版本 | 字节数 | SHA-256 |
|---|---:|---:|---|
| `GyIme-0.12.2.dll` | 0.12.2 / 0.12.2 | **269,824** | **`9BFE40433B1D211F1CFCBD5DF51A4636FC30071A462093A7CD78888C72A7274F`** |
| `GyImeHost-0.12.2.exe` | 0.12.2 / 0.12.2 | 666,624 | `52D2F07B0A9C5D3BFD77666F54FBE1D0BF96A69B972D2E83F4E7F0830D39766F` |
| `GyImeHealth-0.12.2.exe` | 0.12.2 / 0.12.2 | 335,360 | `716405B0B577D69EDD760D6250E58AFDFEF21A1D6CAC981F22DA80175FF5104A` |
| `GYInputSetup-0.12.2.exe` | 产品版本 0.12.2 | 10,275,953 | `2E8579D2B30D7261EFD3CB32779F14CD4F4B43F1DE1D12940CA9118B8C8FCFD6` |
| `GYInput-0.12.2.zip` | 不适用 | 11,604,921 | `D5662540E9F8D9AAA4E983BCC185EE7997849BB1F33B334A8B7DC6DD84E44A2A` |
| `rime.dll` | — | 2,885,632 | `7567D9403103AEBEA9717032E113E32EC1E0DF2AE13AE0BF00E3753BDA37B684` |

公开 0.12.2 `release.json`：`schemaVersion=2`，`releaseId=gy-2026.08.13-windows-0.12.2-thinkpad-test`，`channel=candidate`，`state=candidate`，`signed=false`，`realApplications=pending`，`pointerPolicy=version-pinned-only`。它能证明包自述身份，不能证明源码身份。

#### 0.12.2 安装态、注册表与进程模块

尚未在本轮审计中切换机器到可信 0.12.2，因此以下项目必须标为 **待采集**，不能用设置页截图或历史记忆代替：

| 项目 | 状态 |
|---|---|
| `install-state.json` 安装版本/激活状态 | 待安装 0.12.2 后采集 |
| HKLM `HostVersion` / `HostPath` | 待采集 |
| TSF CLSID `InprocServer32` | 待采集 |
| Firefox/Chrome/Word/Explorer 实际模块 | 待重启并逐进程采集 |

### 3.2 0.12.11 目标

#### 源码与构建身份

| 项目 | 结果 |
|---|---|
| 源码分支 | `codex/gy-0.12.11-runtime-host-supervision` |
| 二进制对应完整提交 | `0c6506b018dfcdf4fe85646f82fd4956020c9c55` |
| GitHub Actions 运行 | `31939189786`，成功 |
| 当前审计分支起点 | `c2559fb0456f1ca9137b863034372490e74b5e5c` |
| 构建后源码变更 | `0c6506b` 之后到审计起点只有发布绑定、批准、R2/站点基础设施和旧审计材料；GY native 源码未再变化 |

#### CI 产物与本机安装文件

| 文件 | PE 文件/产品版本 | 字节数 | SHA-256 | CI 与安装文件 |
|---|---:|---:|---|---|
| `GyIme.dll` | 0.12.11 / 0.12.11 | 322,560 | `428676C1494920F17D0B673982F1A12E15D77D5D100C731FF9450409425FA4D4` | 一致 |
| `GyImeHost-0.12.11.exe` | 0.12.11 / 0.12.11 | 679,936 | `EC46F02AE97E71C0256830F8FEFF9522653DA172178A76512EA09DC9D53EC8AD` | 一致 |
| `GyImeHealth-0.12.11.exe` | 0.12.11 / 0.12.11 | 335,360 | `EE1E9FBC4C8185F62AF52BE970BC87C16AD6D3DE898C116B4449EDBDDF7AFE29` | 一致 |
| `GYInputSetup-0.12.11.exe` | 产品版本 0.12.11 | 7,988,269 | `2FA7CC1BB4D6493A5BEB33AAD073697FB755ED7BF1AAF1D44BBA186159EE1F4D` | CI/公开回读一致 |
| `GYInput-0.12.11.zip` | 不适用 | 8,499,758 | `55C939392B8EAD3BF09517C75E29F3FBB3BB5FB128C3A7D3E38EA9C787BCB11E` | CI 产物 |

#### 本机安装与激活状态（2026-08-17 采集）

`C:\Program Files\GYInput\install-state.json`：

| 字段 | 值 |
|---|---|
| `version` / `coreVersion` / `hostVersion` | 0.12.11 / 0.12.11 / 0.12.11 |
| `activationState` | `active` |
| `registryVerified` | `true` |
| `requiresClientReload` | `false` |
| `previousCoreVersion` | 0.12.10 |
| `installedAtUtc` | `2026-08-17T00:42:45.5610859Z` |

注册表：

| 项目 | 实际值 |
|---|---|
| HKLM `SOFTWARE\GYInput\HostVersion` | `0.12.11` |
| HKLM `SOFTWARE\GYInput\HostPath` | `C:\Program Files\GYInput\versions\0.12.11\GyImeHost-0.12.11.exe` |
| TSF CLSID | `{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}` |
| `InprocServer32` | `C:\Program Files\GYInput\tsf-0.12.11\GyIme.dll` |

首次重启前的进程实际加载模块（混载现场）：

| 进程 | PID（采样时） | 实际 GyIme.dll | PE 版本 | 与注册表一致 |
|---|---:|---|---:|---|
| Firefox | 5884 | `C:\Program Files\GYInput\tsf-0.12.10\GyIme.dll` | 0.12.10 | **否** |
| Chrome | 17684 | 同上 | 0.12.10 | **否** |
| Explorer | 9276 | 同上 | 0.12.10 | **否** |
| Windows Search | 7140 | 同上 | 0.12.10 | **否** |
| Codex/ChatGPT | 16972 | 同上 | 0.12.10 | **否** |
| Word | 未运行 | 未采集 | — | 待测 |
| WeChat | 未运行 | 未采集 | — | 待测 |

由此可见，`requiresClientReload=false` 只证明注册表写入已回读，并没有证明长寿命客户端已卸载旧 TSF DLL。

#### 正常重启后的 0.12.11 身份闭环（2026-08-17 14:47 采集）

用户保存工作并正常重启后，Windows 启动时间为 2026-08-17 14:30:09；当前登录会话的 Explorer、Search、Firefox、Codex 和 Host 均重新建立。此时：

| 对象 | PID | 实际路径/版本 | 结论 |
|---|---:|---|---|
| Explorer | 4984 | `tsf-0.12.11\GyIme.dll` / 0.12.11 | 一致 |
| Windows Search | 8256 | `tsf-0.12.11\GyIme.dll` / 0.12.11 | 一致 |
| Firefox | 13704 | `tsf-0.12.11\GyIme.dll` / 0.12.11 | 一致 |
| Codex/ChatGPT | 14464 | `tsf-0.12.11\GyIme.dll` / 0.12.11 | 一致 |
| `msedgewebview2` | 11880 | `tsf-0.12.11\GyIme.dll` / 0.12.11 | 一致 |
| GY Host | 13644 | `versions\0.12.11\GyImeHost-0.12.11.exe` | 一致 |

注册表、状态文件、进程 DLL 与 Host 因而形成了纯 0.12.11 环境。重启前的“无中文候选”可以确定由混载导致；用户在纯 0.12.11 环境仍报告其他问题，所以后续现象必须作为 0.12.11 自身行为分别记录，不能再归入旧 DLL 混载。

## 4. 完整差异的可验证边界

因为 0.12.2 缺少可验证源码，不能声称存在“0.12.2 源码→0.12.11 源码”的真实逐行 diff。本报告提供两条互补证据链：

1. **精确包级比较：** 公开 0.12.2 ZIP 与 CI 0.12.11 ZIP，包括二进制、安装/升级/激活/回退脚本和清单。
2. **精确源码级比较：** 最早可验证的 0.12.5 源码快照 `71bdfdf` 到构建 0.12.11 的提交 `0c6506b`。

完整源码逐行差异可由以下固定对象重现：

```powershell
git diff --binary --full-index 71bdfdfbf6fbd2fc9a20609786d10554e10e4c55 0c6506b018dfcdf4fe85646f82fd4956020c9c55
```

GitHub Compare：<https://github.com/Christine3749/gyshurufa/compare/71bdfdfbf6fbd2fc9a20609786d10554e10e4c55...0c6506b018dfcdf4fe85646f82fd4956020c9c55>

### 4.1 0.12.2 ZIP→0.12.11 ZIP 完整文件差异

0.12.2 解包后共有 50 个文件、25,135,405 字节；0.12.11 解包后共有 35 个文件、17,875,176 字节。逐文件 SHA-256 比较得到 4 个新增、21 个内容变化、10 个逐字节相同、19 个移除：

| 状态 | 数量 | 完整文件列表 |
|---|---:|---|
| 新增 | 4 | `payload/GyIme-0.12.11.dll`<br>`payload/GyImeHealth-0.12.11.exe`<br>`payload/GyImeHost-0.12.11.exe`<br>`Recover-GYIncompleteRegistration.ps1` |
| 内容变化 | 21 | `AutoUpdate-GYInput.ps1`<br>`Finalize-GYClientReload.ps1`<br>`Get-GYKeepHealth.ps1`<br>`Get-GYLoadedClientState.ps1`<br>`GYInputTransaction.ps1`<br>`Install-GYInput.ps1`<br>`LICENSES/english-frequency-words-CC-BY-SA-4.0.txt`<br>`Migrate-GYLegacyInstallEntries.ps1`<br>`payload/release-notes.txt`<br>`payload/rime-data/shared/build/luna_pinyin.schema.yaml`<br>`payload/rime-data/shared/luna_pinyin.schema.yaml`<br>`payload/SHA256SUMS.txt`<br>`Prune-GYOldVersions.ps1`<br>`Register-GYInputActivationTasks.ps1`<br>`release.json`<br>`Repair-GYInput.ps1`<br>`Rollback-GYInput.ps1`<br>`Set-GYKeyboard.ps1`<br>`Sync-GYEnglishLexicon.ps1`<br>`Validate-GYInput.ps1`<br>`VERSION` |
| 逐字节相同 | 10 | `LICENSES/librime-BSD-3-Clause.txt`<br>`LICENSES/rime-data-license.txt`<br>`payload/english-lexicon/english.tsv`<br>`payload/gy.ico`<br>`payload/rime-data/shared/build/default.yaml`<br>`payload/rime-data/shared/build/luna_pinyin.prism.bin`<br>`payload/rime-data/shared/build/luna_pinyin.reverse.bin`<br>`payload/rime-data/shared/build/luna_pinyin.table.bin`<br>`payload/rime-data/shared/build/SHA256SUMS.txt`<br>`payload/rime.dll` |
| 移除 | 19 | `payload/GyIme-0.12.2.dll`<br>`payload/GyImeHealth-0.12.2.exe`<br>`payload/GyImeHost-0.12.2.exe`<br>`payload/rime-data/shared/AUTHORS`<br>`payload/rime-data/shared/default.yaml`<br>`payload/rime-data/shared/essay.txt`<br>`payload/rime-data/shared/gy_pinyin.schema.yaml`<br>`payload/rime-data/shared/key_bindings.yaml`<br>`payload/rime-data/shared/LICENSE`<br>`payload/rime-data/shared/luna_pinyin_fluency.schema.yaml`<br>`payload/rime-data/shared/luna_pinyin_simp.schema.yaml`<br>`payload/rime-data/shared/luna_pinyin_tw.schema.yaml`<br>`payload/rime-data/shared/luna_pinyin.dict.yaml`<br>`payload/rime-data/shared/luna_quanpin.schema.yaml`<br>`payload/rime-data/shared/Makefile`<br>`payload/rime-data/shared/pinyin.yaml`<br>`payload/rime-data/shared/punctuation.yaml`<br>`payload/rime-data/shared/README.md`<br>`payload/rime-data/shared/symbols.yaml` |

包内脚本的逐行比较以公开 ZIP 中实际脚本为准，而不是以后来的仓库文件替代 0.12.2。除版本号和换行差异外，主要语义变化集中在 `Install-GYInput.ps1`、`Finalize-GYClientReload.ps1`、`Register-GYInputActivationTasks.ps1`、`Set-GYKeyboard.ps1`、`Repair-GYInput.ps1`、`Rollback-GYInput.ps1`、`Validate-GYInput.ps1` 和新增恢复脚本；根因相关行已在第 5—6 节逐项引用。

### 4.2 0.12.5 可验证快照→0.12.11 完整变更文件表

| # | 状态 | 文件 | + | - | 分类 |
|---:|:---:|---|---:|---:|---|
| 1 | A | `.github/workflows/firefox-0.12.11-candidate.yml` | 95 | 0 | 测试/追溯 |
| 2 | M | `gy输入法/native/Build-GYThinkPadCandidate.ps1` | 7 | 3 | 构建 |
| 3 | M | `gy输入法/native/CMakeLists.txt` | 2 | 1 | 版本/构建 |
| 4 | M | `gy输入法/native/RELEASE.md` | 1 | 1 | 发布 |
| 5 | M | `gy输入法/native/ReleaseManifest.psm1` | 1 | 1 | 发布 |
| 6 | M | `gy输入法/native/VERSION` | 1 | 1 | 版本 |
| 7 | M | `gy输入法/native/installer/Finalize-GYClientReload.ps1` | 2 | 2 | 激活 |
| 8 | M | `gy输入法/native/installer/GYInput.iss` | 42 | 1 | 安装 |
| 9 | M | `gy输入法/native/installer/Install-GYInput.ps1` | 28 | 3 | 安装/激活 |
| 10 | M | `gy输入法/native/installer/InstallerSmoke.ps1` | 35 | 6 | 安装测试 |
| 11 | A | `gy输入法/native/installer/Recover-GYIncompleteRegistration.ps1` | 144 | 0 | 注册恢复 |
| 12 | M | `gy输入法/native/installer/Register-GYInputActivationTasks.ps1` | 18 | 11 | 启动/登录激活 |
| 13 | M | `gy输入法/native/installer/Repair-GYInput.ps1` | 18 | 0 | 修复 |
| 14 | M | `gy输入法/native/installer/Rollback-GYInput.ps1` | 15 | 0 | 回退 |
| 15 | M | `gy输入法/native/installer/Set-GYKeyboard.ps1` | 94 | 1 | 键盘恢复/Host 对账 |
| 16 | M | `gy输入法/native/installer/Validate-GYInput.ps1` | 38 | 0 | 验证 |
| 17 | M | `gy输入法/native/installer/Verify-GYRelease.ps1` | 11 | 3 | 发布验证 |
| 18 | M | `gy输入法/native/package.ps1` | 1 | 0 | 打包 |
| 19 | M | `gy输入法/native/src/GyIme.cpp` | 329 | 56 | Firefox/TSF 无文本日志 |
| 20 | M | `gy输入法/native/src/GyImeHost.cpp` | 185 | 10 | Host 身份/运行监督 |
| 21 | M | `gy输入法/native/src/HostProtocol.h` | 8 | 0 | Host/DLL 协议 |
| 22 | M | `gy输入法/native/src/HostProtocolSmoke.cpp` | 18 | 2 | 协议测试 |
| 23 | M | `gy输入法/native/src/HostedPinyinEngine.cpp` | 80 | 8 | Host 身份/恢复 |
| 24 | M | `gy输入法/native/src/HostedPinyinEngineSmoke.cpp` | 31 | 0 | Host 测试 |
| 25 | M | `gy输入法/native/src/InputScopeCache.h` | 63 | 8 | HWND/PID/TTL 诊断 |
| 26 | M | `gy输入法/native/src/InputScopeCacheSmoke.cpp` | 11 | 3 | scope 缓存测试 |
| 27 | M | `release/RELEASE_WORKFLOW.md` | 1 | 0 | 发布流程 |
| 28 | A | `release/approvals/0.12.10.json` | 18 | 0 | 发布批准 |
| 29 | A | `release/approvals/0.12.8.json` | 18 | 0 | 发布批准 |
| 30 | A | `release/approvals/0.12.9.json` | 18 | 0 | 发布批准 |
| 31 | A | `release/notes/0.12.10.txt` | 8 | 0 | 发布说明 |
| 32 | A | `release/notes/0.12.11.txt` | 9 | 0 | 发布说明 |
| 33 | A | `release/notes/0.12.6.txt` | 8 | 0 | 发布说明 |
| 34 | A | `release/notes/0.12.7.txt` | 9 | 0 | 发布说明 |
| 35 | A | `release/notes/0.12.8.txt` | 7 | 0 | 发布说明 |
| 36 | A | `release/notes/0.12.9.txt` | 7 | 0 | 发布说明 |
| 37 | M | `release/release.json` | 16 | 10 | 发布清单 |

### 4.3 用户指定重点文件的差异结论

| 文件 | 0.12.5 快照→0.12.11 | 审阅结论 |
|---|---|---|
| `GyIme.cpp` | 有变化 | 主要增加不记录文本的 TSF/Firefox 生命周期追踪；关键生命周期修正已经存在于 0.12.5 快照 |
| `HostProtocol.h` | 有变化 | 加强 Host/DLL 版本化协议说明/校验 |
| `InputScopeCache.h` | 有变化 | 增加 PID/HWND/TTL 诊断和失配原因，不是简繁策略 |
| `GyImeHost.cpp` | 有变化 | 严格 Host 身份、实例和候选 UI 防御 |
| `HostedPinyinEngine.cpp` | 有变化 | 严格版本 Host、短期限时、0.12.11 即时恢复 |
| `InputMode.h` | **无变化** | 0/1/2 分别为简体/繁体/英文，并单独持久化 `LastChineseMode` |
| `InputScopePolicy.h` | **无变化** | URL、密码、PIN 等 direct/sensitive 域策略 |
| `KeyPolicy.h` | **无变化** | 按键语义没有在 0.12.6—0.12.11 改动 |
| `EnglishCandidatePolicy.h` | **无变化** | 英文候选大小写/commit generation 策略不变 |
| `CandidatePresentationPolicy.h` | **无变化** | 中文网格与英文条/列表分离策略不变 |
| `CandidateAppearancePolicy.h` | **无变化** | 95%/100% 外观策略不变 |
| `CandidateWindow.cpp` | **无变化** | 候选窗布局绘制没有在该范围改动 |
| `PinyinEngine.cpp` | **无变化** | 简繁输出、英文/中文候选路由没有在该范围改动 |

这意味着：如果真实 0.12.11 测试出现数字、大小写、英文网格、候选截断、95% 外观或简繁回归，不能仅凭 0.12.11 提交说明归因；首先必须排除旧 DLL、错 Host、旧设置和不可验证的 0.12.2→0.12.5 变化。

## 5. 按功能分类的代码审阅

### 5.1 中文输入与组合态

- `GyIme.cpp:717-747`：异步动作先校验 `ITfContext`；生命周期动作（Cancel、CommitRaw、CommitRawForDirectInput）绕过 mode generation 过期过滤。
- `TsfEditSessionPolicy.h:10-28`：`WasAccepted` 使用 `SUCCEEDED`，因此 `TF_S_ASYNC` 被视为已接受；生命周期动作和 direct-input 首字母保留策略被独立表达。
- `GyIme.cpp:1034-1053`、`1738-1753`：URL scope 迟到时请求原始提交；只有请求失败才本地释放组合对象。
- `PinyinEngine.cpp:240-250`、`521-525`：代码试图用 Rime `zh_hans` 和 Windows `LCMapStringEx` 双重规范化简繁，但实机可执行探针证明这不是完整转换链：`LCMapStringEx` 不转换 `後/爲/麽`，而安装包又缺少 Schema 所引用的 `t2s.json` 及 OpenCC 词典。

### 5.2 英文补全与按键

- `InputCapturePolicy.h:24-37`：Tab 只在英文组合且存在候选时捕获；英文数字是原样输入，不是选词键。
- `GyIme.cpp:460-541`：数字/日期字面量、英文 Tab/Space/Enter 和中文 1—5 选词路径彼此分开。
- `EnglishCandidatePolicy.h:60-99`：根据用户输入形态保留全大写、首字母大写和小写；`125-133` 校验异步 generation。
- 这些文件在 0.12.5 快照到 0.12.11 之间未改动。

### 5.3 中英文模式与简繁体

- `InputMode.h:14-20`：简体=0、繁体=1、英文=2。
- `InputMode.h:91-201`：`InputMode` 与 `LastChineseMode` 在注册表/INI 中分开持久化；英文模式不应覆盖上次中文脚本。
- `HostProtocol.h:83-175`：每次查词携带 `input_mode` 和 `mode_generation`，响应必须与请求快照一致。
- 本机采样时 `InputMode=0`、`LastChineseMode=0`，即设置本身是简体。重启前无中文候选由 DLL/Host 版本失配解释；重启后直接查询纯 0.12.11 Host，mode=0 仍返回 `後面`、`爲什麽`，证明另有简体转换覆盖不完整的问题。
- `luna_pinyin.schema.yaml:67,122-126` 声明 `simplifier@zh_hans` 与 `opencc_config: t2s.json`；0.12.11 实际安装目录只含 Schema 与预编译 table/prism/reverse 文件，没有 `t2s.json` 或 OpenCC 字典。因此 `set_option("zh_hans")` 不能形成可验证的完整简化链。
- `NormalizeOutputScript()` 的 Windows API 回退只做区域映射，不是完整的一对多/词组 OpenCC 转换。本机探针：`後面→後面`、`爲什麽→爲什麽`、`我是誰→我是谁`、`臥室→卧室`；这与用户观察到“简体里夹很多繁体”的不一致模式完全相符。

### 5.4 候选栏、展开状态与外观

- `CandidatePresentationPolicy.h:16-76`：候选目的明确区分中文转换、英文补全和英文纠错；英文只能进入 strip/list，中文才能进入 grid；数字捷径只属于中文。
- `GyImeHost.cpp:619-627`：Host 对目的/表面再次防御，错误网格/列表状态会被清理。
- `CandidateAppearancePolicy.h` 和 `CandidateWindow.cpp` 在可验证的 0.12.5→0.12.11 区间未变。候选遮挡、截断和 95% 协调性只能通过两个真实版本的视觉测试确认。

### 5.5 Firefox、浏览器输入域与 TSF 生命周期

- `GyIme.cpp:699-715`：记录 `OnPushContext`、`OnPopContext` 和 `OnEndEdit`。
- `GyIme.cpp:1192-1201`：专门处理 Firefox 地址栏在 `OnEndEdit` 才公开 URL scope 的情况。
- `GyIme.cpp:1253-1274`：scope 刷新使用异步读编辑，避免在 `OnEndEdit` 内同步锁/重入。
- `GyIme.cpp:1276-1305`：Host scope 缓存按当前焦点 HWND/PID/TTL 守卫。
- `InputScopeCache.h` 的 0.12.6—0.12.11 变化主要是可诊断性；scope 取值和文本存储没有记录用户文本。
- `GyIme.cpp:987-999,1894-1899`：direct URL/email/path 域不是硬边界。Shift 会翻转 `input_scope_manual_override_`，使 `EffectiveInputScopeDirect()` 在 `input_scope_direct_=true` 时仍返回 false。纯 0.12.11 Firefox 日志随后出现 `scope_direct=1` 的 `key.test.eaten action=letter` 和 `composition.start`；这正是地址栏显示中文候选的直接原因。
- 上述 direct-field 手动中文覆盖首次可验证加入于 `38377d4cfd46ffdf4d9bc8b0c784293903a0b1b6`；`71bdfdf` 仅把密码/PIN 改为不可覆盖，仍保留 URL/email/path 覆盖。按当前验收标准，该策略必须回退为“所有 direct 域均不捕获、不候选”。
- Firefox 的 `OnPushContext`/`OnPopContext` 确实会发生：纯 0.12.11 日志记录了多个 context push/pop 和地址栏 context 由 `...251A0` 切到 `...284B0`。但截图对应的候选错误发生时，scope、context 与 HWND 都已匹配；不能把它误归因于 context 更换。

### 5.6 Windows Search / XAML 组合范围

- Windows Search 的日志位于 AppContainer 专用目录 `...\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\AC\Temp\GyIme.trace.log`；普通 `%TEMP%` 日志无法代表 SearchHost 是否收到 TSF 回调。
- SearchHost PID 8256 加载纯 0.12.11 后，`Activate`、按键 Sink、Context Sink、普通文本 InputScope、`StartComposition`、连续 `SetText` 和 `SetSelection` 均为 `S_OK`；编辑请求在该宿主同步完成。用户同时观察到 `wu→uw`，因此不是 Host 不可用或 mode generation 丢弃。
- `GyIme.cpp:1454-1510` 使用 `ITfInsertAtSelection::InsertTextAtSelection(TF_IAS_QUERYONLY)` 创建零长插入范围，再反复对 `composition_->GetRange()` 执行 `SetText`，最后把同一 range collapse 到 `TF_ANCHOR_END` 并 `SetSelection`。该实现只记录 HRESULT，不记录 range 端点关系或宿主回读 selection；XAML TextStore 可返回 `S_OK` 但以不同锚点重力解释更新，符合“后键插到前面”的实测。
- 提交 `b1d4d527dbc403db5c9231fc1de3f91a32b992f3` 首次改用 `TF_IAS_QUERYONLY` 并宣称修复 Search/Explorer 锚点，但当前真实 0.12.11 仍失败。由于可信 0.12.2 没有源码，不能据此宣称它是首次引入回归的提交；它是首次可验证的相关实现/修复尝试。

### 5.7 Host/DLL 协议与运行监督

- 提交 `449b229` 首次要求 DLL、注册表 HostVersion、Host 路径版本和实际 Host 完全一致，防止旧 DLL 消费新 Host 候选。
- `HostedPinyinEngine.cpp:217-267`：不匹配时失败关闭；0.12.11 增加一次即时启动/恢复，但不能让已经加载的 0.12.10 DLL安全调用 0.12.11 Host。
- 这项严格身份校验本身应保留；真正的问题是安装完成器在客户端已经加载旧 DLL 后才切换全局注册表。

### 5.8 安装、重启、激活与回退

- 0.12.2 的键盘恢复使用 HKCU `RunOnce`；它可能在激活前被 Windows 消耗，导致重启后账户只剩 ENG。
- 0.12.11 `Install-GYInput.ps1:155-179` 改为耐久 HKCU `Run`，并加入 `-ReconcileHost`，这是可保留改进。
- `Register-GYInputActivationTasks.ps1:48-70` 同时注册 ONSTART 与 ONLOGON，且都延迟 20 秒。
- `Finalize-GYClientReload.ps1:204-227` 用 BootId 禁止同一次启动内激活；一旦机器重启过，任意后续登录触发均会通过，所以它不能保证切换发生在 Explorer/Search/浏览器加载 DLL 之前。
- `Finalize-GYClientReload.ps1:155-171` 只凭注册表回读写 `requiresClientReload=false`，没有调用已存在的加载模块扫描来证明客户端一致。

### 5.9 版本号与构建可追溯性

- 0.12.11 的 `VERSION`、CMake、Inno、release manifest、CI run 和哈希清单可相互验证。
- 0.12.2 清单缺 `sourceCommit`，仓库又缺 tag/branch，是不可补救的历史追溯缺口。

## 6. 故障—代码—提交映射

| 故障 | 状态 | 代码位置/机制 | 首次可验证提交 |
|---|---|---|---|
| Firefox 首字母后卡住 | 旧根因已确认；最终 20 标签待测 | 旧 `CancelComposition` 只接受 `S_OK`，`TF_S_ASYNC` 后提前 Reset；旧 `ApplyEdit` 丢弃所有 generation 变化；URL late scope 取消首字母；同步读锁 | 首个可验证修正 `71bdfdf`；首次引入 **不可证明** |
| Firefox 地址栏出现中文候选/被 GY 捕获 | **纯 0.12.11 已确认失败** | direct URL 域允许 Shift 设置 `input_scope_manual_override_`，使 `EffectiveInputScopeDirect()` 失效；日志在 `scope_direct=1` 时仍 `key.test.eaten` 并启动组合 | 首次可验证引入 `38377d4`；`71bdfdf` 保留该行为 |
| 重启后只剩英文、无中文候选 | 当前根因已确认 | 旧客户端 DLL + 新注册 Host 严格失配；0.12.2 另有 RunOnce 丢失风险 | 当前晚激活首次出现于 `9621dae`；严格身份来自 `449b229` |
| Windows Search 无中文/`wu→uw` | **纯 0.12.11 已确认失败；倒序机制已收敛、补丁待实测** | SearchHost 正常激活并成功完成组合编辑；`TF_IAS_QUERYONLY` 零长范围 + 反复 `SetText` + 本地 collapse/end 在 XAML TextStore 中没有回读验证，宿主可 `S_OK` 但保留错误锚点；另有 Shift 把 mode 0 切为 2 | 相关实现首次可追溯 `b1d4d52`；首次坏提交因 0.12.2 无源码而不可证明 |
| 简体模式夹杂繁体 | **纯 0.12.11 已确认失败** | Schema 引用但安装包缺 `t2s.json`/OpenCC 数据；Windows `LCMapStringEx` 回退不转换 `後/爲/麽`；实际 Host mode=0 返回 `後面`、`爲什麽` | `LCMapStringEx` 路径首次可追溯 `dde8a70`；首次坏提交不可证明 |
| 数字无法输入/被当选词键 | 待真实复测 | 当前 `InputCapturePolicy.h:35-37,61-63` 与 `GyIme.cpp:460-541` 路由正确 | 首个可追溯实现 `71bdfdf`；首次坏提交不可证明 |
| 中文模式出现英文候选，英文模式出现拼音候选 | 待真实复测 | 当前协议携带 mode/generation；Pinyin/English 路由隔离；错 Host 会失败关闭而非混用 | 严格协议加强 `449b229` 及后续；最早坏提交不可证明 |
| 英文展开误入中文网格 | 源码策略已隔离，待视觉复测 | `CandidatePresentationPolicy.h:16-76`、`GyImeHost.cpp:619-627` | 首个可追溯修正 `71bdfdf` |
| 大小写不能保留 | 源码策略正确，待真实复测 | `EnglishCandidatePolicy.h:60-99` | 首个可追溯实现 `71bdfdf` |
| 候选文字遮挡/截断 | 待视觉复测 | CandidateWindow/Appearance 的过挂、宽度、截断策略 | 可验证区间未改；首次坏提交不可证明 |
| 95% 排版不协调 | 待视觉复测 | `CandidateAppearancePolicy.h`、`CandidateWindow.cpp` | 可验证区间未改；首次坏提交不可证明 |
| 安装新版本仍运行旧 DLL | **本机已确认** | Windows 不会从长寿命进程中热卸载 TSF DLL；晚激活造成注册表与进程模块分裂 | 一般机制非单一提交；本次竞态由 `9621dae` 首次引入 |
| 不同软件表现不同 | **已确认机制** | 每进程加载时刻不同；TSF TextStore/InputScope/上下文生命周期不同；每个进程可持有不同 DLL | 非单一提交；本机模块扫描直接证明 |

### 6.1 关键提交链

| 提交 | 作用 | 审计判断 |
|---|---|---|
| `71bdfdfbf6fbd2fc9a20609786d10554e10e4c55` | 0.12.5 源码交接；包含 TSF async、scope、候选/按键大改 | 多项行为的首个可验证快照，但不是可信 0.12.2 |
| `38377d4cfd46ffdf4d9bc8b0c784293903a0b1b6` | 为 direct 浏览器/账号字段加入 focus-local 中文覆盖 | **Firefox 地址栏候选策略的首次可验证坏提交** |
| `b1d4d527dbc403db5c9231fc1de3f91a32b992f3` | 组合起点改为 `TF_IAS_QUERYONLY`，目标是修 XAML 锚点 | 相关实现/修复尝试；纯 0.12.11 Search 仍出现倒序，不能视为已修复 |
| `dde8a7085187fca664d7c156839d2c17d30d4f00` | 引入简繁模式与 `LCMapStringEx` 输出规范化 | 首个可追溯简繁回退实现；本机证明覆盖不完整 |
| `e6b9888` | Firefox/TSF 无文本追踪 | 诊断改进，可保留 |
| `449b229` | 拒绝混合版本 Host | 安全边界可保留；与晚激活组合后暴露无候选 |
| `8a29125` | 恢复缺失 Host 元数据 | 可保留，但要受事务/加载一致性约束 |
| `1a900e3` | helper 移出临时目录 | 可保留 |
| `b89b3bf` | 版本固定 Host 对账 | 可保留；不能替代客户端 DLL 重载 |
| `9621daed7c2598d42e2ec6f3769df4405855e1e8` | ONSTART/ONLOGON 冗余任务及 20 秒延迟 | **本机激活竞态首次坏提交** |
| `0c6506b018dfcdf4fe85646f82fd4956020c9c55` | 已注册 Host 不可用时立即恢复 | 对新 0.12.11 DLL 有用；不能修复旧 DLL/新 Host 混载 |

由于 0.12.2—0.12.5 没有连续可验证源码历史，不能对这一段做诚实的 `git bisect`。对 0.12.5—0.12.11 的安装提交链，源码和本机时间线已经将晚激活首次定位到 `9621dae`；仍需在隔离测试中以该提交的父/子包复现实测，才达到“代码+真实测试”的完整二分标准。

## 7. 真实 Firefox TSF 生命周期证据（不记录用户文本）

日志格式仅记录事件类别、HRESULT、对象地址、generation、scope 布尔值、PID/HWND 和按键类别；`detail=key-category-only`，没有记录实际用户字符串。

### 7.1 重启前 0.12.10：late URL scope 的异步提交路径

证据环境：Firefox PID 5884，实际模块 `C:\Program Files\GYInput\tsf-0.12.10\GyIme.dll`，版本 0.12.10。关键序列：

```text
seq=542 event=key.test.enter action=letter ctx=...24550 composition=0 detail=key-category-only
seq=556 event=edit.request.enter action=append ctx=...24550
seq=562 event=composition.start hr=0x00000000
seq=568 event=edit.session.exit action=append ctx=...24550 composition=...262B0
seq=569 event=edit.end.enter action=read-callback ctx=...24550 composition=...262B0
seq=570 event=input-scope.signal.tsf ctx=...24550 composition=...262B0 aux0=1 aux1=1
seq=572 event=input-scope.signal.cache ctx=...24550 composition=...262B0 detail=match
seq=574 event=input-scope.direct hr=0x00000000 value=1
seq=578 event=edit.request.enter action=commit-raw-direct ctx=...24550 composition=...262B0 current_gen=4 queued_gen=4
seq=579 event=edit.request.result action=commit-raw-direct session=0x00040300 ctx=...24550 composition=...262B0
seq=583 event=edit.end.exit action=read-callback ctx=...24550 composition=...262B0
seq=584 event=edit.session.enter action=commit-raw-direct ctx=...24550 composition=...262B0
seq=585 event=edit.apply.enter action=commit-raw-direct ctx=...24550 current_gen=4 queued_gen=4
seq=588 event=composition.commit.end-result action=raw hr=0x00000000
seq=589 event=composition.commit.exit action=raw ctx=...24550 composition=0
seq=606 event=key.test.enter action=letter ctx=...24550 detail=key-category-only
seq=607 event=input-scope.key-cache ctx=...24550 detail=match
seq=610 event=key.test.pass.direct action=letter ctx=...24550 detail=key-category-only
```

解释：Firefox 在首键后没有更换该关键 `ITfContext`；URL scope 在 `OnEndEdit` 出现；`RequestEditSession` 返回 `TF_S_ASYNC` 后组合对象没有提前释放；生命周期提交没有因 generation 变化丢弃；异步会话在同一 context 成功原样提交首字母；后续字母直接放行。日志中另外出现的 `edit.apply.drop.context-mismatch` 仅针对已经过期的 `refresh-input-scope` 读请求，没有丢弃组合提交/取消生命周期动作。

限制：这不是 0.12.11 进程证据，也没有完成 20 个新标签页的首字母不丢、不重、后续连续和无候选窗验收。因此它支持“修正路径存在并真实执行”，不支持“0.12.11 已全面通过”。

### 7.2 重启后纯 0.12.11：direct 地址栏被手动覆盖

证据环境：Firefox 主进程 PID 13704，实际模块 `C:\Program Files\GYInput\tsf-0.12.11\GyIme.dll`，文件版本与 SHA-256 已在 3.2 节闭合。用户截图显示地址栏组合与中文候选；截图 98,042 字节，SHA-256 `A94F83350A3EF917FE792CD263A3BFE828D1D1D10E9FB0D24A75BFC123C2356A`。对应无文本日志快照 30,835,688 字节，SHA-256 `A681471A50FF2AE8F128BAA5A294A0FCA27D5803646D1D00C238177A7D108BDB`。关键序列：

```text
seq=550  event=key.test.eaten action=modifier ctx=...251A0 scope_direct=1 current_gen=3
seq=568  event=key.test.eaten action=letter   ctx=...251A0 scope_direct=1 current_gen=4
seq=582  event=composition.start hr=0x00000000
seq=606  event=key.test.eaten action=letter   ctx=...251A0 composition=...27440 scope_direct=1
...
seq=1716 event=context.push ctx=...2CC80 related=...251A0
seq=1729 event=context.pop  ctx=...284B0
seq=1746 event=context.push ctx=...284B0 related=...2CC80
seq=1822 event=key.test.eaten action=modifier ctx=...284B0 scope_direct=1 current_gen=11
seq=1832 event=mode.apply.enter aux0=2 aux1=0 ctx=...284B0 scope_direct=1
seq=1833 event=mode.apply.exit  aux0=0 ctx=...284B0 scope_direct=1 current_gen=12
seq=1840 event=key.test.eaten action=letter ctx=...284B0 scope_direct=1 current_gen=12
seq=1854 event=composition.start hr=0x00000000
```

解释：Firefox 的确更换/推入/弹出过 `ITfContext`，但候选错误不是因为 context 检查丢弃。错误出现时 context 稳定、URL direct scope 已知、焦点 HWND 与 Host cache 匹配；Shift 之后 mode 从 EN(2) 变为简体(0)，随后 direct 地址栏字母仍被捕获。唯一能同时解释 `scope_direct=1` 与捕获行为的是 `input_scope_manual_override_` 令 `EffectiveInputScopeDirect()` 返回 false。该路径是确定根因。

### 7.3 重启后纯 0.12.11：Windows Search AppContainer 日志

SearchHost PID 8256 实际加载 0.12.11 DLL。日志保存在 `MicrosoftWindows.Client.CBS` AppContainer 的 `AC\Temp`，快照 568,754 字节，SHA-256 `BEDE97600E15CFD786A31404382942453A6380070DB72C1F4C87DD7F7C4F5823`；日志同样不记录用户文本。用户结果截图 78,617 字节，SHA-256 `96E194D8C77F7954950F46FED4980D79F37C3857BD4804F77434F14E1CD86C42`。

关键事实：

- `activate.keystroke-manager`、`activate.advise-key-sink`、`activate.advise-focus-sink` 均为 `S_OK`。
- context `...53A780` 被识别为 `scope_known=1 scope_direct=0 scope_sensitive=0`，即正常可中文文本域。
- 两个连续 letter 动作分别创建/更新 composition `...350980`；`composition.start`、`composition.set-text`、`composition.selection` 和 `edit.session.exit` 均为 `S_OK`，没有 context/generation drop。
- 用户实测却得到倒序 `uw`。由于日志按隐私要求只记录 letter 类别而不记录字母值，当前证据能证明“两个更新均被 GY 接受且宿主返回成功”，不能仅凭日志独立重建 `wu` 的字符顺序；倒序结论由用户目视截图提供。
- mode 序列还记录 `mode.apply.enter aux0=0 aux1=2`（简体→英文）和稍后 `aux0=2 aux1=0`（英文→简体）。因此在英文段无中文候选是正确执行了全局 Shift 切换，而不是 Host 崩溃；倒序仍是独立缺陷。

### 7.4 重启后纯 0.12.11：简体转换可执行探针

通过 protocol v4 直接查询正在运行的 Host（仅 lookup，不改设置或学习数据），请求和响应快照一致：

| 查询 | mode=0 简体首选/部分候选 | mode=1 繁体首选/部分候选 |
|---|---|---|
| `houmian` | `後面`、`後`、`厚`、`后` | `後面`、`後`、`厚`、`后` |
| `weishenme` | `爲什麽`、`爲甚麽` | `爲什麼`、`爲甚麼` |
| `woshishui` | `我是谁`、`卧室`、`卧式` | `我是誰`、`臥室`、`臥式` |

Windows API 探针又证明 `LCMapStringEx(zh-Hans, LCMAP_SIMPLIFIED_CHINESE)` 返回：`後面→後面`、`爲什麽→爲什麽`、`我是誰→我是谁`、`臥室→卧室`、`繁體字→繁体字`。这不是随机状态或 UI 缓存，而是转换表覆盖不完整；安装目录缺少 `t2s.json`/OpenCC 数据使 Rime 层没有提供完整补偿。

## 8. 测试状态

### 8.1 自动化测试

0.12.11 CI 运行 `31939189786` 成功。主测试执行 20 个非 GUI 测试并全部通过，另行执行 `GyHostedPinyinEngineSmoke` 与 Installer smoke。工作流明确排除或隔离了环境绑定的 GUI/TSF 测试，因此 CI 不能替代真实 Firefox、Word、微信和 Windows Search 验收。

### 8.2 同条件真实应用矩阵

重启后机器已形成纯 0.12.11 环境，0.12.11 真实矩阵开始执行。Windows Search、Firefox 地址栏和简繁模式已有可执行/截图/日志证据；未实际观察的项目仍保持未完成：

| 应用/场景 | 0.12.2 | 0.12.11 | 完成条件 |
|---|---|---|---|
| 记事本 | 待测 | 待测 | 进程模块身份闭合；中文、英文、按键矩阵 |
| Word | 待测 | 待测 | 同上；Word 版本 16.0.20228.20190 |
| Firefox 地址栏 | 待测 | **失败（已复现 2 个 direct context）** | direct scope 下仍显示中文候选；20 标签稳定性尚未完成 |
| Firefox 网页输入框 | 待测 | 待测 | 正常中文候选/提交 |
| Chrome 地址栏 | 待测 | 待测 | 地址栏 direct input；首字母/连续输入 |
| 微信 | 待测 | 待测 | 正常中文候选/提交；WeChat 4.1.12.26 |
| Codex/ChatGPT 输入框 | 待测 | **部分通过、部分失败** | 能提交中文；用户报告切换后偶发无中文/字母向前插，需按独立步骤复现 |
| Windows 搜索 | 待测 | **失败** | 纯 0.12.11；用户观察 `wu→uw`，AppContainer 日志证明组合/选择 API 全部 `S_OK` |
| 密码框 | 待测 | 待测 | 不显示候选，不记录文本 |
| 中英文/简繁切换 | 待测 | **失败** | mode=0 Host 仍返回 `後面`、`爲什麽`；Shift mode 切换本身有日志，跨应用体验仍需复测 |
| `woshi` | 待测 | 待测 | 中文模式给中文候选，英文模式保持英文策略 |
| `woman5` | 待测 | 待测 | `5` 不被错误吞掉/选词 |
| `GPT-5` | 待测 | 待测 | 大小写和连字符、数字完整保留 |
| `Windows 11` | 待测 | 待测 | 系统版本 10.0.26200，构建 26200 |
| Tab/Space/Enter/Esc/方向键 | 待测 | 待测 | 中/英文各自语义正确 |
| 95%/100% 候选外观 | 待测 | 待测 | 截图比对，无遮挡/截断/比例失衡 |

纯 0.12.11 普通进程无文本日志初始快照：23,577,001 字节，SHA-256 `FB84AD79991140739A7B0824993ABB07E64255AD5FD446753100872A4F7B1C99`；包含 Firefox 复现的后续快照：30,835,688 字节，SHA-256 `A681471A50FF2AE8F128BAA5A294A0FCA27D5803646D1D00C238177A7D108BDB`；SearchHost AppContainer 快照：568,754 字节，SHA-256 `BEDE97600E15CFD786A31404382942453A6380070DB72C1F4C87DD7F7C4F5823`。这些快照保存在本地审计证据目录，不纳入 Git。

正确的下一步测试顺序：

1. 已完成：保存用户工作并正常重启 Windows；重启后采集 0.12.11 `install-state.json`、注册表与目标进程实际 `GyIme.dll`，确认当前已启动对象全部为 0.12.11。
2. 进行中：先为已失败的 Firefox direct override、Windows Search XAML range 和简体转换建立最小补丁设计与可重复回归测试；未修复版本无需重复做“通过性”结论，但仍需完成其余 0.12.11 矩阵以划定影响面。
3. 经用户明确同意后，安装已验证 SHA-256 的 0.12.2 基线并正常重启；再次闭合状态/注册表/模块身份。
4. 在相同 Windows、应用版本、显示缩放和测试串下完成 0.12.2 全矩阵。
5. 如要恢复用户日常环境，应按用户指定版本恢复；不在审计中擅自部署新版本。

## 9. 已确认根因、仍待证明的假设

### 已确认根因

1. 重启前无中文候选：0.12.10 DLL 实际驻留 + 0.12.11 Host 注册，严格版本校验失败关闭。
2. 安装后仍运行旧 DLL：TSF DLL 是进程内模块，注册表切换不热替换已运行进程。
3. 0.12.11 本机晚激活：延迟 ONSTART/ONLOGON 在 Explorer 等加载旧 DLL 后才切换全局注册表；BootId 条件不足以保证登录会话安全。
4. Firefox 历史首字母卡住：旧代码错误处理 `TF_S_ASYNC`、generation 过滤生命周期、late URL scope 丢弃原始首键、同步 scope 读锁的组合问题。
5. Firefox 0.12.11 地址栏候选：direct URL 域的 `input_scope_manual_override_` 绕过硬直输边界；不是 InputScope 未识别，也不是新旧 DLL 混载。
6. 简体 0.12.11 泄漏繁体：安装包缺少 Schema 引用的 OpenCC `t2s.json`/词典，Windows locale-map 回退又覆盖不完整。
7. Windows Search 0.12.11 字母倒序：TSF API 均返回成功但 XAML TextStore 保留错误组合/选择锚点；现实现没有做范围端点回读与宿主兼容分支。根因层级已收敛，具体最小 API 序列仍需在补丁构建中 A/B 验证。

### 仍待证明

1. 可信 0.12.2 二进制在本机各应用的真实表现。
2. 身份闭合后的 0.12.11 在其余指定应用的真实表现。
3. Firefox 0.12.11 连续 20 标签页的失败频率；当前已不满足“无中文候选”门槛，不能标记通过。
4. 数字、模式交叉候选、英文展开、大小写、候选遮挡和 95% 外观是否在 0.12.11 二进制中有可复现回归。
5. `9621dae` 父/子构建在隔离测试中的二分复现（当前源码和时间线已定位，但尚未执行两包真实对照）。

## 10. 可以保留、应当回退与最小修复顺序

### 可以保留的 0.12.11 改进

- 不记录用户文本的 TSF 生命周期追踪。
- `TF_S_ASYNC` 接受语义、生命周期 generation 例外、late URL 原样提交和异步 scope 读取。
- 严格 Host/DLL 版本身份与 mode/generation 协议。
- Host 请求期限、不可用 Host 的受限即时恢复。
- 安装注册表事务、状态回读、版本化目录、旧注册不完整恢复。
- HKCU `Run` 键盘恢复取代易丢的 `RunOnce`，以及 Host 对账。
- 英文/中文候选目的隔离、大小写策略、数字字面量策略（目前源码无回归证据）。

### 应当回退或重新设计的改动

- 回退 `9621dae` 引入的“延迟 ONSTART + 延迟 ONLOGON 可直接切换全局 TSF 注册”语义；至少不能在已启动 Explorer/Search/浏览器的登录会话中切换。
- `requiresClientReload=false` 不能只依据注册表，应在进程模块仍有旧 GyIme.dll 时保持需要重载/重启状态。
- 不应让 Host 对账脚本把“Host 已启动”误当成“所有客户端 DLL 已一致”。
- 回退 `38377d4` 的 direct-field 中文覆盖语义：URL、email、账号、文件路径和密码域均应为不捕获、不组合、不候选的硬边界；Shift 只能改变离开 direct 域后的全局模式，不能在当前地址栏打开中文组合。
- 不再把 `LCMapStringEx` 当作完整简繁转换器。要么随包提供并校验 OpenCC 配置/词典并让 Rime `zh_hans` 真正生效，要么引入同等完整、可测试的离线转换表；安装健康检查必须用 `後面/为什么/里面/发展` 等覆盖集做简繁断言。
- Windows Search 需要 XAML/CoreText 专用的组合范围回读与锚点策略；不能再把 `SetText/SetSelection == S_OK` 当作视觉顺序正确。最小补丁必须在不记录字符内容的前提下记录 range/selection 的相对端点与长度。

### 最小修复顺序（仅建议，本轮不改代码）

1. 先修激活原子性：只允许在目标客户端尚未启动的真正启动阶段切换，或在检测到旧模块时保持 staged/pending 并要求明确重启。
2. 把加载模块扫描纳入激活成功条件和 `requiresClientReload` 计算；保留严格 Host/DLL 身份，禁止用放松版本校验掩盖竞态。
3. 删除所有 direct 域的 `input_scope_manual_override_` 捕获路径，并为 Firefox/Chrome 地址栏建立“无候选”自动策略测试和真实 20 标签测试。
4. 补齐、哈希校验并实际加载完整 OpenCC 简繁数据；对 Host protocol mode=0/1 建立成组断言，覆盖 `後/后`、`爲/为`、`麽/么`、`誰/谁`、`臥/卧`。
5. 给 TSF 日志加入不含文本的 range/selection 相对端点与长度，针对 SearchHost A/B 验证组合创建/更新方案，直到 `wu` 连续重复不倒序。
6. 对 `9621dae` 父/子包做真实二分，覆盖登录、快速启动、多次登录和 Explorer 早启动。
7. 最小补丁完成后执行 0.12.2/0.12.11/修复候选版全矩阵与 Firefox 20 标签测试；审计阶段不创建版本、不打包、不部署。

## 11. 最终交付门槛

在以下条件全部满足前，本报告不标记 Final，也不提交“所有故障已修复”的结论：

- 0.12.2 与 0.12.11 各自完成状态—注册表—模块身份闭环。
- 两版本在同条件下完成全部应用/按键/字符串/外观矩阵。
- Firefox 每版本至少 20 个新标签页测试完成并保存不记录文本的日志证据。
- 报告补入实际结果、截图/日志哈希及所有待测项结论。
- 报告与 0.12.11 源码在独立 GitHub 分支形成明确提交；不包含 `.artifacts/`、安装包或临时文件。
