# GY 输入法 Firefox 地址栏首字母后无法继续输入 — Codex 调查交接报告

日期：2026-08-14

状态：**公开候选版仍可复现；今天编写的新补丁尚未进入公开安装包，不能据此判定补丁有效或无效。**

目标平台：Windows 11、最新版 Firefox、GY 输入法候选通道

---

## 0. 给接手 Codex 的首要结论

请先停止继续猜代码。当前最重要的问题是**源码、编译 DLL、公开安装包没有形成同一条可核验的版本链**。

用户从 `shurufa.wang` 下载并测试的是：

- 显示版本：`0.12.5`
- 安装包大小：`10,281,708` 字节
- 安装包 SHA-256：`E1426857E25BE1CE9176234B440FFB0604703253331F8D9561D2FB2888EF5025`
- 本机旧安装包生成时间：2026-08-13 23:55:34

而本会话针对 Firefox 新编译的 DLL 是：

- 路径：`gy输入法/native/build-thinkpad-0.12.5/bin/Release/GyIme.dll`
- 大小：`273,408` 字节
- SHA-256：`1D427406539385343E1B5B718A11E317DD2C511B1A9C30FE5E07C040FC554576`
- 生成时间：2026-08-14 08:37:20

因此，公开安装包比 Firefox 补丁更早生成，补丁没有进入用户刚测试的安装包。用户所说“问题依旧还在”，准确含义是：

> 旧的公开 0.12.5 仍然存在 Firefox 故障；今天的新补丁尚未获得真实 Firefox 验证。

不要再使用同一个 `0.12.5` 版本号覆盖不同二进制。后续修复候选应升为 `0.12.6`，并为安装包、ZIP、DLL、源码提交分别记录不可变的哈希和提交号。

---

## 1. 用户实际观察到的故障

### Firefox

1. 打开最新版 Firefox。
2. 使用 `Win + Space` 选择 GY。
3. 点击 Firefox 地址栏。
4. 输入第一个字母，例如 `w`。
5. 地址栏显示第一个 `w`，并出现 GY 的“简”状态浮标。
6. 继续敲击后续字母，地址栏不再正常接收输入。

结果：**第一字母之后输入被卡住。**

### 对照组

同一台 ThinkPad 的 Chromium 浏览器地址栏可以连续输入诸如 `wxldfa`。这说明：

- 不是整台电脑的键盘失效；
- 不是所有浏览器都失效；
- 问题高度集中在 Firefox 地址栏的 TSF 文本存储、输入域识别或组合态生命周期。

---

## 2. GitHub 源码现状：当前不能从远端获得完整 0.12.5 源码

仓库：`https://github.com/Christine3749/gyshurufa.git`

准备中的完整源码交接分支：`codex/gy-0.12.5-source-handoff`

本机当前状态：

- 当前分支：`codex/gy-0.10.62-sync-cursor`
- 本地 HEAD：`fb76cf4`（`release(ime): prepare isolated 0.10.90 candidate`）
- 远端同名分支：`119038b`
- GitHub 没有可确认对应公开 `0.12.5` 的完整源码提交或标签；
- 大量 0.12.x 源码仍是本机未提交修改；
- 多个 0.12.x 新文件还是 Git 未跟踪文件；
- `GyIme.cpp` 相对当前 Git 基线已有约 816 行新增、182 行删除，不能把旧远端代码当成当前产品代码。

尤其下列 Firefox 修复文件目前不在远端可克隆的完整提交里：

- `gy输入法/native/src/TsfEditSessionPolicy.h`
- `gy输入法/native/src/TsfEditSessionPolicySmoke.cpp`
- 以及 `GyIme.cpp`、`CMakeLists.txt` 中尚未提交的相关改动。

### 接手 Codex 的 GitHub 获取规则

在负责人发布一个**只包含完整、可构建产品源码且不包含本机构建产物/私密文件**的新分支前，不要直接基于旧远端分支修复。

获得准确分支名后，使用：

```powershell
git clone https://github.com/Christine3749/gyshurufa.git
cd gyshurufa
git fetch --all --tags --prune
git switch <负责人提供的完整源码分支>
git rev-parse HEAD
git status --short
```

要求 `git status --short` 为空，并将 `git rev-parse HEAD` 的结果写进调查结论。若负责人不能提供确切提交号，停止发布动作，先完成源码快照。

---

## 3. 上一轮分析与未实机验证的补丁

### 3.1 初步分析

Firefox 将地址栏的内部 `inputmode="mozAwesomebar"` 映射为 Windows `IS_URL` 输入域。GY 可能在首字母已经进入组合态之后，才从 `OnEndEdit` 得知当前字段是 URL。

原代码存在两个可疑点：

1. `RequestEditSession` 接受异步编辑时会返回成功状态 `TF_S_ASYNC`，原 `CancelComposition()` 只把 `S_OK` 当作成功，可能在异步编辑尚未执行前就清除了本地组合对象。
2. URL 输入域触发模式代际变化后，排队中的旧代际清理可能在 `ApplyEdit()` 被当作过期任务直接丢弃。

这可以解释：第一个字母已经进入 Firefox 文本存储的组合态，但组合态没有被正确结束，随后 Firefox 与 GY 对编辑锁/组合状态的认识不一致。

### 3.2 今天写入但未进入公开安装包的修改

涉及：

- `gy输入法/native/src/GyIme.cpp`
- `gy输入法/native/src/TsfEditSessionPolicy.h`
- `gy输入法/native/src/TsfEditSessionPolicySmoke.cpp`
- `gy输入法/native/CMakeLists.txt`

修改意图：

- 把所有成功的 `HRESULT`（包括 `TF_S_ASYNC`）视为已接受的异步编辑；
- 生命周期编辑不因输入模式代际改变而被丢弃；
- Firefox 在首字母之后才报告 URL 输入域时，把这个首字母按原文提交，再切换为直输；
- 非敏感 URL 字段保留首字母；密码/PIN 等敏感字段不得用同样方式保留内容；
- 添加 `GyTsfEditSessionPolicySmoke` 时序回归测试。

静态/自动验证结果：

- Release DLL 编译通过；
- Firefox 时序策略测试通过；
- 不依赖前台 GUI 的 24 项相关测试全部通过；
- `GyInputScopeCacheSmoke` 在无前台窗口的自动终端里返回 `exit=2`，这是测试环境没有 `GetForegroundWindow()`，不是该策略断言失败；
- **尚未使用包含本补丁的新安装包在真实 Firefox 地址栏测试。**

源码交接分支提交前已从 Git 暂存快照导出到全新目录验证：

- CMake 使用 Visual Studio 2022 x64 从零配置成功；
- `GyIme.dll`、`GyImeHost.exe`、`GyImeHealth.exe`、候选窗实验工具及 Firefox 专项测试均从该快照编译成功；
- 排除需要真实前台窗口的 `GyInputScopeCacheSmoke` 后，24/24 项测试通过；
- `GyInputScopeCacheSmoke` 必须在交互式桌面运行，自动终端没有前台 HWND 时返回 `exit=2`。

### 3.3 不应过早下结论

上述补丁只是一个有依据的候选修复，不是已确认根因。Firefox 仍可能在首字母后切换 `ITfContext` 或文档管理器，使已排队的生命周期编辑因为下列检查而被丢弃：

```cpp
if (!edit_context || edit_context != context_) return S_OK;
```

同时，当前 `OnPushContext` 与 `OnPopContext` 仍为空实现。它们是否与 Firefox 地址栏首字母后的上下文切换有关，必须由真实跟踪日志证明，不能继续凭猜测修改。

---

## 4. 接手 Codex 的调查任务

### 阶段 A：先做版本证据链

1. 从负责人提供的完整源码分支克隆；记录分支名和 commit SHA。
2. 核对 `native/VERSION`、`release/release.json`、安装程序文件版本和 DLL PE 文件版本一致。
3. 构建新候选 `0.12.6`。
4. 记录：
   - `GyIme.dll` SHA-256；
   - `GyImeHost.exe` SHA-256；
   - 安装包 SHA-256 和字节数；
   - ZIP SHA-256 和字节数；
   - 对应 Git commit SHA。
5. 安装后从注册表的 GY CLSID `InprocServer32` 读取实际加载 DLL 路径，对该文件重新计算 SHA-256。不能只看设置页版本文字。

只有“源码提交 → 构建 DLL → 安装包 → ThinkPad 已安装 DLL”四者闭环后，才能开始判断补丁结果。

### 阶段 B：增加不记录输入内容的 TSF 跟踪

当前跟踪信息不足。请至少记录以下事件，但严禁记录用户输入字符、候选文字、剪贴板或字段内容：

- 进程 ID、线程 ID；
- `OnSetFocus` 的旧/新 document manager 指针；
- `OnPushContext`、`OnPopContext` 的 context 指针；
- `SetContext` 的旧/新 context 指针；
- `OnTestKeyDown`、`OnKeyDown` 只记录虚拟键类别/序号，不记录可还原的文本；
- `RequestEditSession` 的 action、外层 HRESULT、session HRESULT；
- `DoEditSession` 的 action、context 指针、edit cookie；
- `mode_generation_`、排队 generation、是否被丢弃；
- `composition_` 是否存在及对象指针；
- `OnCompositionTerminated`；
- 输入域是否 known/direct/sensitive，来源是 TSF、native password 还是 Host cache；
- `ApplyInputMode`、`CommitRawForDirectInput`、`CancelComposition`、`ClearComposition` 的进入与结果。

指针只用于单次进程内关联生命周期，不上传为遥测，不永久保存。

### 阶段 C：在真实 Firefox 上捕获第一字母时序

必须使用最新版 Firefox 真实地址栏，不得只用自建 Win32/RichEdit 测试窗口替代。

最小矩阵：

1. 新开 Firefox，聚焦地址栏，输入 `woshi`。
2. 新标签页地址栏输入 `www.example.com`。
3. 已有文字的地址栏按 `Ctrl+L` 后重新输入。
4. 连续新建 20 个标签页，每次首字母不同。
5. 从地址栏切到网页普通文本框，输入 `woshi` 并选择“我是”。
6. 再回地址栏输入英文，确认恢复直输。
7. 对照 Chrome/Edge、记事本、Word，确认没有新回归。

每次失败要同时保存：

- Windows 版本；
- Firefox 完整版本；
- GY 实际安装 DLL 路径和哈希；
- 当前 GY 模式；
- 从聚焦地址栏到第二个按键之后的完整 TSF 跟踪；
- 录屏或连续截图。

### 阶段 D：用证据判断以下竞争假设

按优先级检查：

1. **异步编辑状态误判**：`TF_S_ASYNC` 是否仍被错误清理。
2. **上下文替换**：Firefox 首字母后是否 push/pop 或更换 context，导致排队编辑被 `edit_context != context_` 丢弃。
3. **组合态提前释放**：本地已释放 `composition_`，Firefox 端仍认为组合进行中。
4. **首字母处理语义错误**：进入 URL 直输时是删除、提交原文还是重复提交。
5. **输入域来源冲突**：TSF 的 `IS_URL`、Host 缓存和当前 HWND 是否引用了不同字段或旧焦点。
6. **回调重入/锁冲突**：在 `OnEndEdit` 中申请读写编辑是否触发 Firefox 特有的重入或延迟顺序。
7. **上下文事件空实现**：只有日志证明 push/pop 与故障相关后，才实现 `OnPushContext`/`OnPopContext`；实现后必须测试旧 context 的组合如何安全收尾。

---

## 5. 验收标准

新版本必须同时满足：

- Firefox 地址栏可从第一个字母连续输入完整字符串；
- 第一个字母不丢失、不重复；
- URL 直输状态不显示中文候选框；
- 地址栏不遗留无法结束的组合态；
- 地址栏与网页文本框之间切换不串状态；
- 网页普通文本框仍可正常中文输入和选词；
- Chrome/Edge、记事本、Word 无回归；
- 连续 20 次新标签页测试无一次卡死；
- 安装后实际 DLL 哈希与本次报告中的候选 DLL 哈希一致；
- 不修改稳定版通道，直到 ThinkPad 真实 Firefox 验收通过。

自动策略测试通过只能作为必要条件，不能替代真实 Firefox 验收。

---

## 6. 接手 Codex 必须交付的结果

1. 有真实日志支撑的根因说明；
2. 最小修复补丁及为什么不会破坏密码字段/普通中文输入的说明；
3. Firefox 真实应用回归证据；
4. 全套自动测试结果；
5. 干净、完整、可重新构建的 GitHub 分支与 commit SHA；
6. `0.12.6` 安装包、ZIP、核心 DLL 的哈希与大小；
7. ThinkPad 的五分钟验收步骤；
8. 在用户真实验收前，不得宣称“已修复”，只能称“候选修复”。

---

## 7. 给接手 Codex 的一句话任务

> 请从负责人提供的完整 GY 源码 GitHub 分支开始，先证明源码、DLL、安装包和 ThinkPad 实际安装文件完全对应，再用不记录用户文本的 TSF 生命周期日志复现最新版 Firefox 地址栏“首字母后无法继续输入”；重点验证 Firefox 是否在首字母后更换 context，以及异步 edit session/组合态是否被提前释放或丢弃。完成真实 Firefox 20 次回归前不要发布，不要覆盖 0.12.5，使用 0.12.6 候选版。
