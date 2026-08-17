# GY Windows TSF 根因修复实施记录

> 日期：2026-08-17（Asia/Shanghai）
> 分支：`codex/gy-windows-tsf-root-fixes-after-0.12.11`
> 起始提交：`c2559fb0456f1ca9137b863034372490e74b5e5c`
> 状态：源码修复与独立回归测试已完成；产品 DLL 的 MSVC 构建、真实应用验收和候选版发布尚未执行。

## 1. 边界

本次修改的是 GY 的 Windows 输入核心：TSF 进程内 DLL、进程外 Host、Rime/OpenCC 数据和安装激活事务。它不是 Windows 内核或驱动程序。目标是受支持的 64 位 Windows 10/11 和其 TSF 应用；在真实应用矩阵通过前，不宣称“全 Windows/所有软件已通过”。

本轮没有修改版本号，没有生成安装包，没有安装/注册新 DLL，没有部署 R2、Vercel、`shurufa.wang` 或稳定版通道。下一个真实候选版必须使用未使用过的新版本号，不覆盖任何已发布的问题版本。

## 2. 四条根因修复

### 2.1 Firefox/Chrome 地址栏：direct 输入域改为硬边界

- 删除 `input_scope_manual_override_` 及其 Shift 临时中文覆盖路径。
- URL、email、账号、文件路径、数字和密码等 direct 域不捕获字母、不建立组合、不显示中文候选。
- direct 域内 Shift 不改写当前域模式；离开后恢复全局保存的中英文模式。
- 策略测试锁定“direct 必须始终是硬边界”。

主要位置：`InputScopePolicy.h`、`GyIme.cpp`、`KeyPolicySmoke.cpp`。

### 2.2 简体模式混入繁体：补齐并强制验证 OpenCC

- 引入 OpenCC 1.4.1 官方配置、`.ocd2` 数据、可确定性测试的 UTF-8 转换表及 Apache-2.0 许可证。
- 新增 `OPENCC_SOURCE.json`，记录上游版本、完整提交号、下载产物哈希和每个数据文件哈希。
- CMake 在配置阶段对数据或许可证缺失直接失败，避免再构建出“schema 声称简体、实际没有转换表”的包。
- Rime 候选、本地短语和学习短语统一通过完整转换表，不再依赖覆盖不完整的 `LCMapStringEx`。
- 回归断言：`houmian -> 后面`、`weishenme -> 为什么`，整个简体候选池不得出现 `後/爲/麽`；本地 `爲什麽|後面` 必须输出 `为什么|后面`。

上游身份：OpenCC 1.4.1，提交 `81223ed87ae53283ef518e2deac34b7971f8a39e`。
官方 portable ZIP SHA-256：`B686B0ECC3723120E214BAB4158DD7B6E784975A312BA18D74F782AF77596742`。
官方 resources ZIP SHA-256：`DB4EA259D43FEDC0D3B928E31C2B9EA6656529217DF18D6C80F814BC748A1DCB`。

主要位置：`runtime/rime/shared/opencc/`、`PinyinEngine.cpp`、`PinyinEngineSmoke.cpp`、`CMakeLists.txt`和三条打包脚本。

### 2.3 Windows Search/XAML 字母倒序：保留组合范围，仅折叠选区克隆

- 旧实现在 `SetText` 后直接折叠从 `ITfComposition::GetRange` 取得的范围，使 XAML/CoreText TextStore 可以在所有 API 都返回 `S_OK` 时仍保留错误锚点，后续字母被放到前面。
- 新实现保持完整组合范围，克隆一个 `ITfRange` 后只折叠克隆到尾部，再用它设置插入点。
- 新组合创建后立即设置查询插入范围为选区，与 Microsoft SampleIME 的锚点建立顺序一致。
- 增加不读取文本的选区回读与端点相对位置日志：只记录 `before/equal/after/unavailable`、HRESULT、context/range 身份和 generation，不记录用户字符。

主要位置：`GyIme.cpp` 的 `UpdateComposition`和 `TraceRangeRelation`。

### 2.4 重启后无中文候选：阻止混载激活，Host 崩溃自恢复

- 删除延迟 20 秒的 ONLOGON 激活路径，只保留无延迟的 SYSTEM ONSTART 任务，并清理旧任务名。
- 在改写 TSF 注册前扫描已加载的受管 `GyIme.dll`。任一客户端已加载时都拒绝切换，保留 pending/旧注册到下一次干净启动，而不是造成“旧 DLL + 新 Host”。
- 扫描只读进程 ID、进程名、DLL 路径/版本；不读窗口文本、命令行、剪贴板或输入内容。
- 保留 Host/DLL 严格版本身份，不用放松协议校验掩盖混载。
- 正常查询或 UI 请求发现 Host 不可用时，在后台工作队列中执行受限流的 `--reconcile-host`；按键路径不等待进程启动。
- 自恢复测试主动关闭 Host 后不再调用 `Prewarm`，仅靠普通 lookup 证明 Host 恢复；卡死 pipe 的硬截止时间测试仍通过。

主要位置：`Finalize-GYClientReload.ps1`、`Register-GYInputActivationTasks.ps1`、`HostedPinyinEngine.cpp`和其 smoke test。

## 3. 验证结果

### 已通过

- OpenCC manifest 内 15 个数据/配置文件的 SHA-256 逐一与实际文件一致。
- `GyImeHealthCheck`：PASS。
- `GyHostedPinyinEngineSmoke`：PASS，包含 Host 关闭后自动恢复。
- `GyHostedPinyinEngineDeadlineSmoke`：PASS。
- `GyKeyPolicySmoke`：PASS。
- `GyEnglishInteractionPolicySmoke`：PASS。
- `GyEnglishLexiconSyncSmoke`：PASS。
- `GyPinyinEngineSmoke`：PASS，包含完整简体候选池和本地短语转换断言。
- `InstallerSmoke.ps1`：PASS，包含无 ONLOGON/无 DELAY、加载客户端拒绝切换、OpenCC 包含和日志隐私断言。
- `git diff --check`：PASS。

### 构建环境限制

本机没有 Visual Studio/MSVC 和 C++/WinRT SDK。MinGW 的 `msctf.h` 缺少 `ITfTextInputProcessorEx`和相关 TSF 常量，因此无法用该工具链编译产品 `GyIme.dll` 或 `GyTsfActivationSmoke`。这是工具链缺失，不是把相关测试记为通过的理由。独立引擎、策略、Host、健康和安装脚本测试使用 MinGW/Ninja 完成。

### 尚未通过的发布门槛

1. 在有完整 MSVC/Windows SDK/C++/WinRT 的构建机生成新的 `GyIme.dll`、Host 和 Health。
2. 使用新的、从未发布过的候选版本号，不覆盖 0.12.11 或任何旧版。
3. 建立源码提交 → 编译 DLL/Host/Health → ZIP/安装包 → ThinkPad 实际安装文件 → 目标进程实际加载 DLL 的完整 SHA-256 链。
4. Firefox 真实地址栏连续新建至少 20 个标签：首字母不丢失/不重复，后续字母连续，无中文候选，无文本生命周期日志保存哈希。
5. Windows Search 重复输入 `wu`，确认不再得到 `uw`；对新增 range/selection 端点日志进行 A/B 对照。
6. 普通文本框要能中文；简体模式验证 `后面/为什么`；再完成 Firefox 网页框、Chrome/Edge 地址栏、记事本、Word、微信、Codex/ChatGPT、Explorer、密码框、中英文切换、数字/大小写/快捷键和 95%/100% 外观矩阵。
7. 真实验收失败时不发布、不切稳定通道；修正后使用下一个新版本号。

## 4. 当前机器仍是 0.12.11

2026-08-17 本轮源码修改后的只读检查：

- `install-state.json`：`version=0.12.11`、`coreVersion=0.12.11`、`activationState=active`、`requiresClientReload=false`。
- 注册表：`HostVersion=0.12.11`；Host 路径为 `C:\Program Files\GYInput\versions\0.12.11\GyImeHost-0.12.11.exe`；TSF 路径为 `C:\Program Files\GYInput\tsf-0.12.11\GyIme.dll`。
- Arc、ChatGPT、Chrome、Claude、Electron、Explorer、Firefox、GyImeHost、Edge WebView2 和 SearchHost 当前实际加载的仍是上述 0.12.11 DLL。

因此，当前机器上继续看到 0.12.11 已知故障，不能解释为“新修复已安装但失败”。新修复还没有编译、安装或加载。

## 5. 总体判定

这四项是针对已经用二进制、日志、注册表、进程模块和可执行探针确认的原因做的结构性修复，不是设置页或显示层补丁。源码层根因覆盖可评为 **8.5/10**；由于产品 DLL 尚未用 MSVC 构建且真实应用矩阵尚未完成，当前发布可信度只能评为 **5/10**。完成哈希链和真机矩阵后才能提高评分并决定是否进入候选通道。
