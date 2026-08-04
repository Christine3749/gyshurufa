# GY 三层架构与更新契约

状态：**已确认的跨端架构基线**。本文件约束 Windows、macOS、账户、同步、AI 与更新；平台只可替换原生实现，不可改变边界。

## 1. 不可妥协的边界

1. 打字必须离线可用。按键、预编辑、候选、选词、上屏路径零网络、零账户依赖。
2. 系统输入接入层极小且稳定；身份、事件入口和 IPC 协议视为兼容性契约。
3. 词库、排序、学习、候选 UI、设置、账户、同步和 AI 不进入系统输入核心。
4. 任一 Engine、Agent、网络或云端故障不得阻塞文字直出；更新保留最后已验证的本地 Engine。
5. 用户名不是身份主键、设备 ID、文件夹名或加密密钥；它只是可修改的资料字段。

## 2. 统一三层

```text
原生应用的文字输入 API
        │
        ▼
稳定 Core ── 本地版本化 IPC ── 可更新 Engine ── 本地 IPC ── Account & Sync Agent
                                                                 │
                                                                 ▼
                                                    Auth / 同步库 / 加密 Relay
```

| 层 | Windows | macOS | 允许职责 | 明确禁止 |
| --- | --- | --- | --- | --- |
| Core | `GyIme.dll`（TSF） | `GYInput.app` 的 InputMethodKit Bridge | 键盘接入、预编辑、上屏、模式、稳定 IPC | 网络、账号、Rime、词库、学习、AI |
| Engine | `GyImeHost` / `GYInputEngine` | 每用户 `GYInputEngine` 服务 | Rime、排序、用户词库、候选与本地 UI | 账户凭证、云端直接调用 |
| Agent | `GYAgent.exe` | 每用户 `GYAccountAgent` | 登录、设备、同步、设置、显式 AI、更新协调 | 键盘截获、同步原始按键 |

候选面板可留在 Engine，或作为 Engine 启动的独立 Panel；它绝不属于 Core。Core 只传递光标锚点、状态和用户选择。

## 3. Core 兼容性与更新

以下字段、入口和消息版本是 Core 契约：

- Windows 的 TSF Profile/CLSID 与 DLL 到 Engine 的本地 IPC；
- macOS 的 `CFBundleIdentifier`、`TISInputSourceID`、`InputMethodConnectionName` 与唯一 InputMethodKit 事件入口；
- `CoreRequest vN` 与 `EngineState vN` 的本地、可校验、带会话 ID 和序号的协议。

Core 只能在兼容性迁移时更新。此类更新必须新建版本、保留可回退快照、停止受影响客户端或明确要求注销；不得宣称已激活。普通 Engine/Agent 更新使用并存版本、健康检查、原子切换和最后已知良好版本回退，不更换 Core。

> 过渡期说明：当前 Mac 尚未完成 Bridge/Engine 拆分。因此覆盖 `GYInput.app` 仍属于 Core 更新，可能需要注销。未完成拆分前，禁止把它当作日常迭代渠道。

## 4. 本地协议与降级

Core 向 Engine 仅发送本地输入请求：模式、会话、编辑动作、预编辑序号和光标锚点。Engine 返回候选、预编辑、选择状态和已确认提交文本。协议必须有超时、版本协商和重复请求保护。

- Engine 更新前保留旧进程，旧进程健康、协议兼容后才切换新进程。
- 更新失败或 Engine 不可用时，Core 连接最后已知良好 Engine；无法连接时取消组合并让应用原样接收按键，不能卡住应用。
- Agent 只能消费已选择的词条聚合、设置变更和用户显式 AI 请求；它不能订阅原始按键流。

## 5. 账户、用户名与设备

| 记录 | 规则 |
| --- | --- |
| `user_id` | Auth 提供的不可变 UUID；所有数据与权限的唯一归属。 |
| `handle` | 可选、大小写规范化后的唯一用户名；可改，改名不迁移数据。 |
| `display_name` | 可选显示昵称；不要求唯一。 |
| `device_id` | 每次设备注册随机生成；附平台、公开标签、公钥、最后在线与撤销时间。 |

首次安装创建纯本地匿名配置，立即可输入。登录仅在设置/Agent 中进行；推荐首版邮件 Magic Link，后续再加 Passkey。登出不破坏本地输入，用户可选择保留或清除本机同步副本。新设备、撤销设备、导出与删除必须由用户可见地确认。

## 6. 凭证、同步与隐私

- Windows 刷新令牌和设备私钥只进 DPAPI/Credential Manager；macOS 只进 Keychain。
- 客户端不得保存密码、Supabase Service Role Key、R2/GCP 凭证或管理员 API Key。
- `profiles`、`devices`、`input_preferences`、`phrase_entries`、`lexicon_events` 必须按 `auth.uid()` 做 RLS。
- 短语、设置、学习同步默认关闭并逐项授权；学习同步是聚合词条事件，不是按键历史。
- GY Link 剪贴板独立授权、端到端加密、带 TTL；服务端只保存密文。撤销设备后轮换设备组密钥。
- AI 只由 Agent 在用户显式操作后调用；输入内容、候选、剪贴板正文不写入上传日志或分析。

## 7. 发布与验收

1. `release/release.json` 是版本真相；Core、Engine、Agent 都记录兼容矩阵与 SHA-256。
2. Core 发布需真实升级/回退测试；Engine 发布需热切换、离线、协议回退和延迟测试；Agent 发布需登录、登出、撤销、断网测试。
3. 所有平台必须验证：未登录、登录、登出、网络断开、Agent 崩溃、Engine 回退和多设备冲突。
4. 公共发布仍需 Windows 可信签名，以及 macOS Developer ID、公证和 stapling。
5. “已知良好”必须通过真实输入验收：常用拼音、候选选择、简繁、英文直出和提交文本；控制器启动或收到按键不能单独作为健康结论。

## 8. 实施顺序

1. 固定并缩小 Windows DLL 与 macOS Bridge；冻结身份、事件入口和 IPC v1。
2. 将 Rime、候选、学习和 Panel 从 Mac Bridge 移至 Engine；只在独立候选环境验证 Engine。
3. 建立本地词库与最后已知良好 Engine 回退。
4. 实现 Account Agent、账户资料和设备列表，不开启自动同步。
5. 经隐私与密钥评审后，逐项开启设置/短语/学习同步；最后才是 GY Link 与 AI。
