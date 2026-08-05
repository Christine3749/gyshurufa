# GY 输入法 × Win11 XAML 输入框光标错位问题 — 技术诊断报告

> 日期：2026-08-05 ｜ 版本：GY 输入法 0.9.40（Windows x64, TSF 架构）
> 作者：Kimi（与 Ethan 联合排查）｜ 状态：**未修复，转交评审**
> 读者：具备 Windows TSF / 输入法开发经验的工程师

---

## 1. 一句话摘要

GY 输入法在 Win32 控件（记事本、命令行、Spotify、Kimi 桌面端）已全部正常，但在 **Windows 11 XAML 输入控件**（Win 键开始菜单搜索框、Explorer 地址栏）中，组合串（preedit）期间的**可见光标位置错误**：停留在旧组合串的末尾而非新文本末尾（如输入 `word` 显示 `wo|rd`）。我方所有 TSF 调用的 HRESULT 均为 S_OK，控件视觉状态却不同步。小狼毫（weasel）等成熟输入法在同类 XAML 宿主上也有大量未根治的 issue，属于业内公认的硬骨头。

## 2. 架构背景（30 秒版）

```
每个 App 进程                    GyImeHost.exe（独立引擎进程）
┌─────────────────┐  命名管道    ┌──────────────────────┐
│ GyIme.dll (TSF) │ ◄═════════► │ rime 引擎 + 候选窗 UI  │
│ OnKeyDown →     │  自定义协议  │ PinyinEngine          │
│ composition 更新 │             └──────────────────────┘
└─────────────────┘
```

- TSF 文本服务（TIP）以 DLL 形式加载进**每个**使用输入法的进程，包括 `TextInputHost.exe`（Win11 开始菜单搜索框的实际输入宿主）、`explorer.exe`、各 App。
- 按键 → `OnKeyDown` → `RequestEditSession` → `UpdateComposition()` 内做 `ITfRange::SetText` 更新组合串 → `ITfContext::SetSelection` 钉住光标。
- 关键代码：`native/src/GyIme.cpp` 的 `UpdateComposition()`（约 L497-547）、`CommitComposition()`（约 L562-595）。

## 3. 现象时间线（实测，全部可复现）

| 时间 | 环境 | 现象 |
|---|---|---|
| 07:27 | Explorer 地址栏 | 组合串 `wo`，**光标在字前**（输入方向看起来倒着走） |
| 07:51 | Win 键搜索框（注销重登后，新 DLL 已生效） | 输入 `word`，显示 `wo|rd`——**光标卡在旧组合串末尾**（位置 2 而非 4） |
| 07:56 | Win 键搜索框（脚本重启 TextInputHost 后） | 输入法完全不介入：裸字母 `woswoshish`，无候选、无组合下划线 |
| 08:02 | Win 键搜索框（同一 TextInputHost 会话） | 仍不介入：裸字母 `woshishui`，无候选。此时光标"正常"仅因为是纯英文直输 |

**已排除的假设**：

- ❌ 旧 DLL 残留：已核验磁盘文件 = 最新构建（GyIme.dll 208384 字节 / GyImeHost 289280 字节，与构建目录完全一致），且做过完整注销重登
- ❌ 注册表类别缺失：5 个 TSF category 已确认注册
- ❌ 我方调用失败：trace 显示所有 TSF 调用 S_OK（见 §4）

## 4. 证据：trace 事件日志分析

诊断版 DLL（`-DGY_IME_TRACE=ON`）在每个 TSF 事件写 `%TEMP%\GyIme.trace.log`。两组对比：

### 4.1 正常进程（pid=12124，记事本，输入 w/o/r/d）

```
activate.begin → keystroke-manager → focus.app=1 → advise-key-sink → advise-focus-sink
key.down(87=W) → composition.start → set-text → caret.tsf → composition.selection (S_OK)
key.down(79=O) → get-range → set-text → caret.tsf(右移) → composition.selection (S_OK)
key.down(82=R) → 同上（caret 继续右移）
key.down(68=D) → 同上
```
全部 S_OK，caret 矩形逐键右移，视觉光标正确。**教科书式正常。**

### 4.2 异常进程（pid=36212，即 TextInputHost，Win 键搜索框）

```
activate.begin → keystroke-manager(S_OK) → focus.app=1 → advise-key-sink(S_OK) → advise-focus-sink(S_OK)
focus.document=1 / context.change=1
focus.document=0/1 反复抖动 ×20+（Start 菜单 UI 内部焦点轮换）
（之后用户敲了 w/o/s/h/i/s/h/u/i 共 9 键——key.down 事件 0 条）
```

**关键结论**：
- 我们的 TIP 在 TextInputHost 里**激活成功**（Activate、按键管理器、key sink 全部 S_OK）
- 但 `OnTestKeyDown/OnKeyDown` **从未被调用**——按键根本没路由给我们，字母以原始英文进入文本框
- 这是故障模式 B（见 §5），它掩盖了故障模式 A 的进一步取证

### 4.3 07:51 的故障模式 A（无 trace，来自截图证据）

当时输入法**有**介入（粉色组合下划线可见、候选窗可见），输入 `word` 后光标显示在位置 2（`wo` 与 `rd` 之间）= **旧组合串的末尾**。此时 `UpdateComposition` 执行的序列是：

```cpp
composition_->GetRange(&range);           // range 覆盖旧组合串 [0,2]
range->SetText(cookie, 0, L"word", 4);    // 替换为 4 字符
ShowCandidates(...);                       // 先量候选窗位置
range->Collapse(cookie, TF_ANCHOR_END);   // 期望锚点 END = 位置 4
context->SetSelection(cookie, 1, &sel);   // 钉光标 —— S_OK
```

视觉光标却在 2，**强烈提示该 XAML 宿主的 range 锚点没有随 SetText 推移到新文本末尾**（SetText 后锚点 END 仍是旧位置 2），或宿主在编辑会话结束后用自身模型覆盖了我们设置的 selection。

## 5. 两个独立的故障模式

### 模式 A：组合期光标错位（主问题）
- **范围**：Win11 XAML 控件（TextInputHost 宿主：开始菜单搜索、锁屏、部分 UWP；Explorer 地址栏 XAML 岛）
- **表现**：`SetText` 全量替换组合串后，可见光标停在旧组合串末尾/开头；连续输入时文本内容正确、仅光标错位
- **注意**：同一代码在 Win11 记事本（也是 XAML！）上通过 `composition.selection` pinning 已修复——说明不同 XAML 宿主的锚点/选区语义**不一致**

### 模式 B：TextInputHost 手动重启后按键不再路由（取证障碍，可自愈）
- **触发**：`Stop-Process TextInputHost`（或等价手段）后进程自动重启，新会话里 TIP 激活成功但按键不路由
- **自愈**：注销重登后恢复（07:51 就是注销后的自然会话，输入法正常介入）
- **佐证**：微软自家输入法/小狼毫也有 TextInputHost 状态机卡死的报告（见 §7-参考 4），微软在 24H2 修过一波
- **对取证的警示**：诊断此类问题时**不要手动杀 TextInputHost**，必须注销重登拿"干净会话"

## 6. 已做过的修复（有效，供参考演进方向）

1. `composition.selection` pinning：`SetText` 后 `Collapse(TF_ANCHOR_END)` + `SetSelection`——**修好了 Win11 记事本**（此前光标在组合串开头）
2. `commit.selection` pinning：`EndComposition` 后同样钉光标到提交文本末尾——修好了"文本倒着累积"（`谁是我` 式倒序）
3. 但以上对开始菜单搜索框（TextInputHost 内层 XAML）**无效**

## 7. 参考资料（同类问题与已知 workaround）

1. **TSF 开发者社区同款问题与 workaround**（wisestudy.cn《TSF输入法开发候选窗口显示位置》问答）：
   - 同款 `SetText → Collapse(END) → SetSelection` 模式在部分宿主失效
   - 有效 workaround A：`StartComposition` 改用 `ITfInsertAtSelection::InsertTextAtSelection(TF_IAS_QUERYONLY)` 取插入 range（让宿主自己给锚点/重力），而非 `GetSelection + Clone + Collapse`
   - 有效 workaround B：StartComposition 后先写入一个 `TF_ST_CORRECTION` 空格再 `Collapse(TF_ANCHOR_START)`，强制宿主重算锚点
2. **微软 SampleIME 官方范式**（github.com/ChineseInputMethod/SampleIME → doc/composition/StartComposition.md）：官方示例的 StartComposition 正是 `TF_IAS_QUERYONLY` 路线，与我们当前的 `GetSelection→Clone` 路线不同
3. **rime/weasel issue #1642**：浏览器/Electron 搜索框"首字母不识别/重复输入"——同类宿主差异问题，社区用 per-app `app_options` 配置兜底
4. **TextInputHost 状态机卡死**（gitcode 博客《Windows 11 下小狼毫输入法卡顿问题分析》）：微软在 24H2 修复；印证模式 B 是系统组件层的已知脆弱点
5. **rime/weasel #1822**：TSF 引擎与 Win11 24H2 XAML 异步框架底层冲突——佐证 XAML 宿主兼容性是全行业痛点

## 8. 建议的修复方向（按优先级）

| 优先级 | 方案 | 理由 | 风险 |
|---|---|---|---|
| P0 | `StartComposition` 改用 `ITfInsertAtSelection::InsertTextAtSelection(TF_IAS_QUERYONLY)` 获取插入 range | 与微软官方 SampleIME 范式对齐；锚点/重力由宿主设定，天然规避"锚点不推移" | 低，属标准路径 |
| P1 | 组合串更新从"全量 SetText 替换"改为"尾部增量追加/退格删除" | 增量编辑不依赖锚点推移语义，兼容性最好（多数宿主对 append 的处理是久经考验的）；还有性能收益 | 中，需处理拼音串任意位置编辑的边缘 case |
| P2 | 参考 workaround B：StartComposition 后写入一个 correction 字符强制宿主重算锚点，再正式开始 | 社区实测对"锚点不更新"宿主有效 | 中，hack 性质，需逐宿主验证 |
| P3 | per-app 策略表（学 weasel `app_options`）：对已知问题宿主（TextInputHost/Explorer XAML）切换兼容模式 | 行业通行兜底方案 | 低，但治标 |
| — | 取证纪律：诊断 XAML 宿主问题时，环境准备必须"注销重登"而非杀进程 | 模式 B 会污染一切实验数据 | — |

## 9. 复现与取证指引（给接手人）

1. 编译诊断版：`cmake -S . -B build-trace -DGY_VERSION=0.9.40 -DGY_IME_TRACE=ON`（事件写 `%TEMP%\GyIme.trace.log`，UTF-16 无 BOM）
2. 部署 trace DLL 后**注销重登**（不要杀 TextInputHost！）
3. 对照组：记事本输入 `word`；实验组：Win 键搜索框输入 `word`
4. 判读要点：实验组是否有 `key.down` → 区分模式 A/B；模式 A 下看 `composition.set-text` 后 `caret.tsf` 矩形是否右移 vs 视觉光标位置
5. 代码位置：`gy输入法/native/src/GyIme.cpp`（`UpdateComposition` L497、`CommitComposition` L562）；协议层 `HostProtocol.h`；设置面板 `SettingsWindow.cpp`

## 10. 附：本次顺带发现并解决的问题

- **学习词库污染**：光标 bug 期间用户误提交生僻字被学习（`woshishui→肟`×8 次、`oshishui→哦是谁` 等），导致候选排序异常。已清空 `settings.ini` 的 `[Learning]` 段（747 条）+ rime `luna_pinyin.userdb`，备份在 `settings.ini.bak-20260805`
- **性能基线**（与本 bug 无关，供参考）：按键全链路 p50 已从 61.5ms 优化至 1.17ms（52 倍），smoke 9/9 通过
