# GY 韧性输入法架构契约（v2）

状态：**目标架构，尚未由当前 macOS 单体实现满足。** 1.0.11 仅是恢复中文输入的临时修复，不是此架构的发布证明。

## 1. 发布门槛

“稍微更新就不能中文”是 Stop-Ship 问题。以下任一情况都不得发布：

1. 修改词库、候选、UI、学习、设置、账号或同步需要替换系统输入 Bundle/DLL。
2. 只有一个可运行中文引擎，或所谓回退版本未通过完整中文验收。
3. Engine、候选 UI、Agent 崩溃会丢失当前拼音、卡住应用或静默上屏英文。
4. 进程存活、控制器激活或收到按键被当作“输入正常”的证据。

输入必须离线；原始按键、预编辑和候选不得经过网络或 Account Agent。

## 2. 五个独立故障域

```text
原生应用
   │
   ▼
① Native Bridge ─ ② Session Guard ─┬─ ③ Engine Slot A（当前）
 TSF / IMK            组合态与重放   └─ ③ Engine Slot B（LKG）
   │                                      │
   │                                      ▼
   └────────── ④ 可选 Candidate UI    ⑤ Local Data Plane
                                             ▲
                                    Control Agent（账号/更新/同步）
```

| 域 | Windows | macOS | 唯一职责 | 绝对禁止 |
| --- | --- | --- | --- | --- |
| ① Native Bridge | `GyIme.dll`（TSF） | `GYInputBridge.app`（InputMethodKit） | 受系统调用、冻结身份、交给 Guard | Rime、词库、Panel、网络、更新逻辑 |
| ② Session Guard | DLL 内极小会话机 | Bridge 内极小会话机 | 序号、组合快照、超时、重放、槽位切换 | 账号、学习、候选排序 |
| ③ Engine Slot | 每用户 `GYEngine` A/B | 每用户 `GYEngine` A/B | 完整 Rime、排序、简繁、选词 | 系统注册、凭证、云端调用 |
| ④ Candidate UI | `GYPanel` | `GYPanel` | 纯渲染与鼠标操作 | 保存唯一组合态、阻塞上屏 |
| ⑤ Data / Agent | `GYAgent` + Local Store | `GYAgent` + Local Store | 词库快照、学习日志、账号、同步、更新 | 截获按键、参与单次按键决策 |

Bridge 的身份是兼容性 ABI：Windows TSF Profile/CLSID；macOS `CFBundleIdentifier`、`TISInputSourceID`、`InputMethodConnectionName` 和唯一事件入口。它们只能在独立、显式的迁移中修改。

## 3. 中文输入的强保证

每个输入会话由 Guard 保存一个有界 `SessionSnapshot`：模式、拼音预编辑、已选词、光标锚点和严格递增序号。每次发给 Engine 的是完整快照而不是不可重放的增量。

1. Guard 先向活跃 Slot 请求候选；响应携带相同序号才可显示或上屏。
2. 超时或崩溃时，Guard 保留 marked text 与快照，连接已预热的 LKG Slot，重放同一快照。
3. 新 Slot 必须给出相同会话序号的完整候选状态；用户已输入的拼音不得消失或变成英文。
4. Candidate UI 失败时，Guard 仍保留键盘数字选词，并使用原生简化候选视图；UI 不在提交链路上。
5. 两个 Engine 均不可用时，明确显示恢复状态，不伪造“正常”。系统中文输入源必须保留为用户的独立逃生路径；不得静默改变用户输入源。

Guard 的本地请求与响应必须版本化、可校验、幂等，且每会话串行。目标预算：常规响应 12 ms，超时探测 40 ms，LKG 切换不超过 150 ms；超时预算不得阻塞宿主应用主线程。

## 4. Engine、数据与候选

每个 Slot 都是**完整可输入**的 Engine：同版本 Rime 二进制、只读基础词典、简繁转换数据和兼容协议。LKG 不是旧 `.app`、不是“能启动”的进程，也不是只会 `nihao → 你好` 的演示表。

- Rime 决定候选顺序、分页与原始索引；产品代码不得用未经语料验证的词频/长度规则删除候选。
- 用户学习以追加事件日志写入 Local Data Plane；Engine 使用可回滚快照，两个 Slot 不直接竞争同一 Rime 写目录。
- 数据迁移必须向后兼容；新数据快照在影子目录构建、校验后原子切换。
- `GYPanel` 只渲染 Engine 返回的模型。它可重启、替换、关闭，不能影响 Space、Enter、数字键和上屏。

## 5. 更新与自动回退

普通更新永远不替换 Bridge/DLL：

1. 下载并验证新 Engine 到未使用槽位，校验签名、哈希、协议版本和数据格式。
2. 在隔离用户数据目录跑语料、简繁、候选选择、分页、英文直出、延迟和崩溃重启测试。
3. 新 Slot 预热成功后，只在当前组合态为空时原子切换；旧 Slot 至少保留到新 Slot 经真实会话健康窗口验证。
4. 失败、重复超时或协议不一致时自动回到 LKG，记录诊断但不上传输入内容。
5. `functionalBaselineVersion` 只能在自动测试和人工真实输入都通过后写入；安装器、版本号、进程存活和日志都不能单独提升基线。

Bridge 更新属于罕见兼容性发布：必须新建版本、保留可验证 Bridge 回退包、明确要求关闭客户端或注销。当前 Mac 因仍是单体 Bundle，任何覆盖安装都属于这种高风险发布；在完成拆分前不得用于日常试验。

## 6. 账户、同步与安全

`GYAgent` 是唯一可联网组件。输入在 Agent 未启动、登出、断网或服务端故障时完全可用。

- `user_id` 是不可变归属；`handle`、昵称和设备标签都可改，绝不能做数据目录、加密密钥或权限主键。
- Windows 令牌/私钥使用 DPAPI；macOS 使用 Keychain。客户端不保存管理密钥或服务端凭证。
- 设置、短语、学习同步逐项 opt-in；学习事件不是原始按键历史。所有云端表按 `auth.uid()` RLS。
- 更新由 Agent 协调，但 Agent 只能提出新 Engine 槽位；它没有替换 Bridge 的权限。

## 7. 现实实施顺序

1. 冻结当前 `GYInput.app` / `GyIme.dll` 的身份与事件入口；停止向其中加入 Rime、UI、恢复或账户功能。
2. 先实现跨平台 `SessionSnapshot v1` 与可执行的双 Slot Engine 测试器，杀死活跃 Engine 后验证未上屏拼音仍可恢复。
3. 建立只读基础词典 + 版本化 Local Data Plane，完成影子迁移与 LKG 槽位切换。
4. 将 macOS Bridge、Windows DLL 接入 Guard；这一步才需要一次明确的系统核心迁移。
5. 抽出 Candidate UI，随后再接学习、设置、Account Agent、同步与 AI。

在第 2 步的故障注入测试通过前，GY 只能是开发候选输入法；日常工作应保留系统中文输入法作为独立后备。

## 8. 必测故障注入

- 输入 `nihao`、`changduan`、长句组合中杀掉 Engine A；预编辑、候选和选择必须由 B 恢复。
- 选中第 2/3/5 个候选后切换 Engine；上屏词不得改变。
- 杀掉 Candidate UI、Agent、网络，输入与数字选词仍正常。
- 更新期间持续在 TextEdit、Terminal、WebKit/Electron 输入；不得要求注销或丢失组合态。
- 仅 Bridge 迁移时才测试注销；迁移后验证旧 Bridge 回退、TIS 注册和真实文本输入。
