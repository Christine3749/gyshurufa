# macOS GY 输入法热升级后无法输入：完整事故报告

- **事故日期：** 2026-08-04
- **影响范围：** 已安装 GY、在同一 macOS 登录会话内连续覆盖升级的用户
- **严重级别：** 发布阻断（已有用户可能完全无法输入）
- **状态：** 已恢复；短期缓解已落地，长期回退与会话健康机制待实现
- **报告版本：** 1.0（根据完整进程、trace 与注销前后对照修订）

## 一句话结论

这不是拼音转换错误，也不是单一代码分支错误。它是一次 **输入法热升级 + InputMethodKit 事件入口切换 + macOS 当前登录会话缓存** 共同造成的故障。

```text
连续覆盖安装
→ 旧 GYInput 进程继续运行
→ 同一 TIS 身份下从 handleEvent: 切换到 inputText:key:modifiers:client:
→ 当前登录会话保留旧 IMK / TIS / 宿主输入会话
→ controller 可以创建和激活，但按键不再路由到新入口
→ 注销重建用户 GUI 会话
→ InputMethodKit 重新协商事件入口
→ text-event 恢复
```

`nihao → 你好` 的转换逻辑在故障期间没有机会执行：控制器根本没有收到按键。

## 用户影响

用户可以在 macOS 输入法菜单中选中 GY，`GYInput` 进程也会运行；部分控制器生命周期日志正常出现。但在 TextEdit 等应用中通过实体键盘输入时，既没有预编辑文本，也没有提交文本。

这类故障危险在于“菜单已选中”“进程存在”“controller 已 activate”都会给出正常假象，而真正决定能否输入的事件路由已经断开。

## 证据时间线

| 时间 | 事件 | 结论 |
| --- | --- | --- |
| 05:42 | PID `68983` 启动，使用旧 `recognizedEvents + handleEvent:` 路径 | 控制器可初始化、可激活。 |
| 05:48 | build 5 覆盖安装 | PID `68983` 未退出，05:49 仍在处理激活；磁盘更新不等于内存中代码更新。 |
| 05:52 | PID `80036` 启动 | 新一代进程开始运行。 |
| 05:54 | build 7 安装，事件入口改为 `inputText:key:modifiers:client:` | PID `80036` 仍运行至 05:58，早期测试实际上仍在测旧代码。 |
| 05:58 | 手动 `pkill`，PID `86846` 启动 | 新二进制已加载，但当前登录会话未完全重建。 |
| 06:00 | build 8 安装；`postinstall` 终止旧进程并拉起 PID `88161` | 证明只重启输入法服务仍不足以恢复。 |
| 06:09 | 注销当前用户 | IMK / TIS、宿主输入会话与相关用户代理一起退出。 |
| 06:10 | 新登录会话；PID `90695` 启动 | trace 出现 99 条 `text-event`，实体键盘输入恢复。 |

最重要的对照：**06:00 已经运行了新二进制，但仍需注销才能恢复。** 因此旧进程是第一层问题，不是完整根因。

## 现象分层：为何能激活，却收不到按键

InputMethodKit 至少涉及两个层面：

| 层面 | 作用 | 故障期间表现 |
| --- | --- | --- |
| 控制层 | 创建 controller、`activateServer:` / `deactivateServer:`、菜单与模式查询 | 正常；可见 `controller-init`、`controller-activate`、`controller-deactivate`。 |
| 输入层 | 决定按键通过 `handleEvent:`、`inputText:key:modifiers:client:` 或 key-binding 路径送达 | 失效；`key-event=0`、`text-event=0`。 |

Apple 的 [IMKServerInput 文档](https://developer.apple.com/documentation/inputmethodkit/imkserverinput) 明确列出这三种事件接收路径，并要求输入法实现所选择路径对应的方法。此次从 `handleEvent:` 切换到当前的 [`inputText:key:modifiers:client:`](../GYInput/Sources/GYInputController.m) 后，已经发生了事件协议变化。

仍存活的宿主 App、Text Services 客户端或 IMK 会话很可能保留了旧协商结果。只杀服务端不能保证客户端输入会话重新协商；注销可以。这是系统内部状态，公开 API 无法直接读取，因此以下结论应表述为 **高度可信推断**，而不是不可证伪的内部实现事实。

## 根因与置信度

### 已确认

- 多次覆盖安装后，旧 Mach-O `GYInput` 进程继续运行。
- PackageKit 替换磁盘 bundle，不会让已运行进程自动加载新代码。
- 仅重启 `GYInput` 进程不足以恢复事件投递。
- 注销再登录后，`text-event` 恢复（本次为 99 条）。
- 故障期没有进入 `nihao → 你好` 转换逻辑。
- 最小 core 阶段没有新的崩溃报告。

### 高度可信推断

- 当前登录会话缓存了旧的 InputMethodKit 事件路由或客户端输入会话。
- 在同一 bundle ID 与 TIS source ID 下，从 `handleEvent:` 切到 `inputText:key:modifiers:client:` 放大了这种会话不一致。

### 风险存在，但不能认定为本次直接根因

- `InputMethodConnectionName` 从 `_Connection` 到 `.Connection` 的改变不安全，仍必须避免普通升级中改动。
- 但注销后 `launchctl` 仍可显示下划线形式，且输入已恢复；因此不能再将这一显示差异视为决定性证据。它可能是系统内部规范化或已注册服务名的展示方式。

### 明确不是本次根因

- `nihao` 映射或候选/提交逻辑。
- plist 语法、代码签名、CPU 架构、最低系统版本。
- 0.9.41 时的 `IMKServer` 启动崩溃；那是已消失的另一组历史问题。
- 免费 Apple 开发者账号。
- 同时出现的 Touch Bar / Control Strip 异常。

## 已恢复的应对方法

### 用户恢复步骤

当 GY 已选中但实体键盘无法输入时：

1. 在 TextEdit 获得焦点后，选择 GY，并观察 `/tmp/GYInput-core.trace` 的新增内容。
2. 实体键盘输入 `nihao` 再按空格。
3. 若有 `controller-activate` 而没有 `text-event`，不要先改拼音、Shift 或候选逻辑。
4. 确认当前运行 PID 晚于新安装二进制的修改时间；先终止**当前控制台用户**的旧 `GYInput` 进程。
5. 如果新 PID 仍没有 `text-event`，保存工作后注销并重新登录。
6. 登录后重新选择 GY，再做真实键盘测试；预期 `nihao` + 空格提交“你好”，并新增至少六条 `text-event`。

若输入源本身不存在或注册异常，再执行“系统设置 → 键盘 → 文本输入 → 编辑”中的移除/重新添加。它是注册修复手段，不应被误当作本次事件路由问题的唯一解释。

### 当前 1.0.7 的已落地修复

- 事件入口统一为 `inputText:key:modifiers:client:`。
- `postinstall` 以登录用户身份注册输入源、终止该用户的旧 `GYInput` 进程，并拉起新 bundle；不会再以 root 影响全部登录用户。
- 启动阶段校验 bundle ID 和连接名非空。
- 构建前清理旧 app bundle，并恢复 macOS 13.0 最低部署目标。
- trace 换行问题已修复；每个新进程写入首条 trace 时记录 PID、build、route 和 bundle，避免不同二进制的日志混淆。
- 当前 TIS 只保留预期的两条 GY 记录，均启用；安装产物签名有效、无新的崩溃报告。

这些改动解决了“继续测到旧进程”的问题；它们**不能强制 TextEdit、Terminal、WebKit/Electron 或 IMK 客户端立即重建输入会话**。遇到事件入口或输入源身份迁移时，仍必须要求注销。

## 当前发布规则

### 不可变升级协议

以下字段在普通版本升级中不得改变：

- `CFBundleIdentifier`
- `TISInputSourceID`
- input mode ID
- `InputMethodConnectionName`
- InputMethodKit 事件入口类型

连接名差异并非本次已证实的唯一根因，但它是已有用户升级兼容性的高风险字段，必须按协议冻结。构建和打包阶段由 [`verify-input-source-contract.sh`](../scripts/verify-input-source-contract.sh) 检查 plist 身份，且要求只创建一个 `IMKServer`；InputMethodKit 不应通过在一个进程中添加第二个“旧端点”来规避迁移。

### 普通代码更新

1. 使用安装脚本终止控制台用户的旧进程并启动新 bundle。
2. 记录运行中的 build、PID、启动时间和事件入口。
3. 验证新进程的启动时间晚于磁盘二进制修改时间。
4. 运行实体键盘冒烟测试。

### 事件入口或输入源配置迁移

这不是普通升级：

1. 发布说明和安装流程必须明确要求用户注销并重新登录。
2. 或采用新的输入源 ID，作为有版本、有回滚方案的正式迁移。
3. 不得假设再次调用 `TISRegisterInputSource` 足以刷新已有客户端输入会话。
4. 必须在已安装旧版的真实用户账户上通过升级测试后才能发布。

## 必须补齐的长期防线

### 1. 进程可归属 trace（已实现）

每个新进程写入的第一条 trace 应包含：

```text
pid=...
build=8
route=inputText:key:modifiers:client:
bundle=wang.shurufa.inputmethod.GYInput
```

不能只写 `controller-init`。多个版本向同一 trace 文件追加时，缺少 PID、build 与路由会让排障人员无法判断日志属于哪个二进制。每个进程的首次 trace 写入均输出这条元数据；旧文件已有内容不会被删除。

### 2. 升级矩阵

每次改变输入法运行时、注册或事件入口前，至少覆盖：

| 场景 | 不注销 | 仅重启 GY | 注销后 |
| --- | --- | --- | --- |
| GY 未启用时安装 | 必测 | 必测 | 必测 |
| GY 已启用但未选中时升级 | 必测 | 必测 | 必测 |
| GY 正在 TextEdit 输入时升级 | 必测 | 必测 | 必测 |
| `handleEvent:` → `inputText:` 迁移 | 必测 | 必测 | 必测 |

每个场景至少用 TextEdit、Terminal，以及一个 WebKit 或 Electron 客户端验证。

### 3. 发布阻断的真实按键验收

[`smoke-test-core.sh`](../scripts/smoke-test-core.sh) 会选择 GY、打开 TextEdit，并要求测试者以**实体键盘**输入 `nihao` + 空格。它必须看到至少六条新增 `text-event`。

Accessibility 或脚本注入文字不能替代该测试，因为它可能绕过本次真正失效的 InputMethodKit 路由。

### 4. 可恢复升级与回退（已实现基础保护）

升级前保留最后一个通过真实键盘验收的版本快照和记录。候选版本只有通过输入验证后才能被标记为“已知可用”。安装器只注册输入源，**不再**杀掉或重启正在运行的 `GYInput`；它将状态写为 `logout-required`，不能假装新核心已激活。

- **修复 GY 注册：** `GYRecovery.sh repair` 仅重建 GY 的输入源记录；若事件入口迁移仍未刷新会话，明确提示保存工作后注销。
- **回退到上一个已知可用版本：** `sudo GYRecovery.sh rollback` 只恢复 `/Library/Application Support/GYInput/rollback` 中已知可用的 GY bundle，保留失败版副本，再注册当前用户输入源；仍要求注销并重新验证输入。
- **建立基线：** 通过实体键盘门禁后执行 `sudo GYRecovery.sh mark-known-good`。下一次安装前才会保存这一版本；没有通过门禁的候选版本绝不会被当作安全回退点。

不要删除 macOS 全局缓存或影响其他输入法；修复操作必须限定到 GY。`test-upgrade-safety.sh` 每次核心测试都会在隔离安装根内验证该快照与 `logout-required` 门禁。回退也不是替代协议稳定性的理由：所有可回退版本仍需保持稳定的 bundle / TIS / connection 身份。

## 支持分流表

| 观测结果 | 优先排查方向 |
| --- | --- |
| 没有 `controller-init` 或 activate | 安装、输入源选择、bundle 注册。 |
| 有 activate，但无 `text-event` | 登录会话/IMK 路由；确认新 PID，之后注销重建会话。 |
| 有 `text-event`，但无法提交“你好” | 控制器、转换、marked text 或客户端兼容性。 |
| 安装后仍运行旧 PID | 安装脚本的用户进程终止与启动逻辑。 |
| 同一版本仅个别应用失败 | 对应客户端输入会话；分别关闭/重开应用，并纳入客户端矩阵。 |

## 结论

本次的本质是：**在同一登录会话和同一输入源身份下热替换了输入法实现及事件协议，却没有让服务端和所有客户端输入会话同时失效重建。**

注销之所以有效，不是它神奇地修复了转换代码，而是它完成了安装脚本无法保证完成的整个用户 GUI 会话冷启动。今后普通升级必须避免协议漂移；任何事件入口或输入源配置迁移必须当作需要注销、回退和完整升级矩阵的发布阻断事项。
