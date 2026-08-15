# GY 输入法 iOS 平台标准（规范优先）

> 生效：2026-08-05 · 状态：v1 锁定
> 适用范围：`IOS-DESIGN.md`、`IOS-V0.1-TASKS.md`、`IOS-BENCHMARK-ANALYSIS.md` 与 `GY_LINK_MOBILE_COMPATIBILITY.md` 的 iOS 条款。
>
> 本文优先级高于上述文档中任何冲突表述。Android 输入法仅可作交互研究对象；iOS 的公开 API、Human Interface Guidelines 与 App Review Guidelines 是最终验收标准。

## 1. 产品与审核硬边界

- 形态为包含 App + `UIInputViewController` 自定义键盘扩展。包含 App 必须提供启用引导、帮助、设置和可访问的隐私政策；键盘扩展本身不得放广告、营销或内购。
- 键盘必须提供输入功能、在无完全访问时仍可完整输入，并在 `needsInputModeSwitchKey` 为真时显示 Globe「下一键盘」键。点击调用 `advanceToNextInputMode()`，长按调用系统输入法列表。
- 扩展不得启动包含 App 或其他 App；唯一允许的跳转例外是系统 Settings。因此扩展内不得设计「打开 GY Link App 后立即回当前 App 粘贴」流程。
- 不使用私有 API、不重定义系统快捷键、不复制微信或 Apple 的图标、文案、视觉资产。

## 2. 完全访问、存储与 librime

- v0.1 固定 `RequestsOpenAccess = NO`。键盘扩展无网络、无麦克风/扬声器访问，且对包含 App 的 App Group 只有只读访问。
- `rime-data` 必须编入 Keyboard Extension target。deploy 目录、userdb、学习和手势临时状态必须写入**键盘扩展自己的沙箱**；不得写入 App Group，也不得承诺与桌面端同一份 userdb 或实时学习同步。
- v0.1 不以 App Group 为运行依赖。若将来需要，容器 App 只能写入版本化、加密的配置/快照供键盘只读；需新增 ADR、迁移方案和无共享数据的降级方案。
- “全量词库”不等于无预算。Apple 没有公开固定的键盘扩展内存上限；45 MB 仅为 GY 内部预警预算，不能当作系统保证。必须在目标真机上做内存压力和恢复测试，并保留充足余量。

## 3. 文本编辑能力边界

- 所有外部文本操作只通过 `UITextDocumentProxy`：`insertText`、`deleteBackward`、`adjustTextPosition(byCharacterOffset:)` 及受限的前后文读取。
- 不假定能取得完整文档、文本选择或稳定的 `documentContextBeforeInput`。上下文为 `nil`、宿主内容变动或扩展重建时，删除恢复/清空撤回只能恢复当前会话中已记录且可验证的操作；否则禁用恢复，绝不猜测或覆盖宿主文本。
- 空格滑动只能移动插入点；不能伪造系统触控板的文本选择能力。长按空格、删除滑动等手势必须先服从 iOS 肌肉记忆和无障碍，再参考 Android 的测量数据。
- 安全文本字段、电话键盘字段通常不允许第三方键盘，宿主 App 也可禁用所有扩展。验证码字段是否调用系统键盘取决于宿主和系统版本，禁止作“必定接管”的产品承诺。

## 4. iOS 交互与无障碍标准

- iOS 系统键盘是布局、键高、按键语义、输入法切换和物理键盘行为的第一基线；微信 Android 版只可作第二参考，绝不作为“行为级复刻”的验收对象。
- v0.1 遵从系统在不同设备和方向上的默认键盘高度，不提供任意高度调节。横屏、小屏与安全区域必须真机验证。
- 每一个可操作键都必须有准确的 VoiceOver 标签、值、操作提示和可访问的命中区域；发布前覆盖 VoiceOver、Voice Control、Switch Control、动态字体/加大显示和 Reduce Motion 相关行为。
- 视觉样式遵循 GY VI，但不得牺牲 iOS 可读性、对比度、触达性或系统切换路径。

## 5. 隐私、供应链与上架

- 输入路径零联网：不请求完全访问，不接入分析、广告、崩溃回传或任何可将输入内容离开设备的 SDK。崩溃诊断不得含输入内容。
- 每个 App、扩展和随附的动态库/第三方 SDK 都要审核 `PrivacyInfo.xcprivacy`；使用 Required Reason API 时声明准确理由。App Store Connect 的 App Privacy 内容和公开隐私政策必须与实际数据流一致。
- 不可预先写“绝不收集数据”作为营销文案，除非发布前数据流审计、依赖审计和法务确认均证明成立。任何未来的 GY Link 网络传输都必须重新评估隐私标签与隐私政策。
- 采用提交时 Apple 支持的最新版 Xcode/SDK；T0 决定最低部署版本，回归矩阵固定覆盖当前正式版和前两个仍支持的大版本。

## 6. GY Link 的 iOS 合规形态

在本项目“不请求完全访问”的产品决策下，键盘扩展不能联网、不能写 App Group、不能启动容器 App。因此：

1. v0.1 不含 GY Link，也不展示暗示可实时拉取的键盘入口。
2. 未来容器 App 可在用户主动打开 App 时拉取端到端加密数据，并写入 App Group；键盘只可读取**已缓存快照**并插入当前输入位置。用户需自行返回目标 App。
3. 不承诺键盘内“实时拉取”、后台同步或 P95 两秒到达。该类能力需要完全访问和用户显式授权；即使未来另行选择，也不得成为基础输入功能的前置条件，且必须经过独立隐私、审核和安全评审。
4. 密码、验证码、私钥、助记词默认不进入任何同步队列；不在服务端日志记录内容正文。

## 7. v0.1 发布门禁

- 无完全访问安装、启用、Globe 切换、离线输入、横竖屏和扩展重建均通过。
- 在标准文本、安全文本、电话键盘、验证码和“宿主禁止扩展”五类场景记录真实系统行为；不把系统差异判作键盘缺陷。
- 候选治理和显示序号到 Rime 原始序号映射单测全绿；文档上下文缺失时不发生错误删除或恢复。
- 真机覆盖小屏、常规尺寸和大屏；覆盖当前正式 iOS 与前两个仍支持版本；完成内存压力、30 分钟稳定性、VoiceOver/Voice Control/Switch Control 验收。
- TestFlight 前完成隐私清单、依赖/Required Reason API 审计、App Privacy 信息、隐私政策、审核备注和录屏证据。

## 8. 依据（发布前再次核验）

- [Apple: Configuring open access for a custom keyboard](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)
- [Apple: Creating a custom keyboard](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard)
- [Apple: Handling text interactions in custom keyboards](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards)
- [Apple: App Review Guidelines 4.4.1](https://developer.apple.com/app-store/review/guidelines/)
- [Apple: Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)