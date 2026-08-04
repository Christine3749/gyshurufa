# GY 输入法 — 下一轮工作交接计划

> 生成时间：2026-08-05 04:28；更新：2026-08-05 05:0x（第 2 轮，新增修复 8/9）。
> 下次开工时把这个文件贴给 Kimi，即可无缝接续。

---

## 一、当前状态：改动已全部落地到代码，等待部署验证

### 已完成的修改（源码已全部提交到工作区）

| # | 修复 | 文件 | 关键内容 |
|---|------|------|----------|
| 1 | trace 诊断开关 | `gy输入法/native/CMakeLists.txt` | 新增 `-DGY_IME_TRACE=ON` 选项，默认 OFF |
| 2 | trace 埋点 | `native/src/GyIme.cpp` | `focus.app` / `focus.document` / `context.change` 三个事件 |
| 3 | 候选文字硬裁剪 | `native/src/CandidateWindow.cpp/.h` | 两遍式自然宽度布局 + `clip_overflow_` 省略号兜底 + 面板上限按 DPI 缩放 |
| 4 | 25 候选翻页锁定 | `native/src/PinyinEngine.cpp` | 深页门槛从"2-8 字词组"放宽为与首页同标准（CJK ≤12 字），池子恢复 75 |
| 5 | zh_hans 选项位置 | `native/src/PinyinEngine.cpp` | 简繁选项移出按键循环，送键前设置一次 |
| 6 | 跨应用候选窗漂移 | `native/src/GyIme.cpp` | `last_caret_valid_` 归属标志 + SetContext/Deactivate 作废 + clipped 接受测量值 + GetGUIThreadInfo 兜底 |
| 7 | 展开网格宽度 | `native/src/CandidateWindow.cpp` | 格子宽度 = clamp(内容宽度, (54+cap)/2 ≈ 82, cap 110)，用户认可的"中间值" |
| 8 | **控制台/Windows Terminal 切不动 GY** | `native/src/Guids.h` + `GyIme.cpp` | 根因：GY 只注册了 1 个类别（TIP_KEYBOARD），缺 IMMERSIVESUPPORT 等。RegisterCategory 改为循环注册 5 个类别（+IMMERSIVESUPPORT/SYSTRAYSUPPORT/UIELEMENTENABLED/COMLESS）。即时修复脚本：`add-tip-categories.ps1`（管理员运行，免注销，新开的控制台即生效） |
| 9 | **记事本候选窗偏上一行** | `native/src/GyIme.cpp` | 根因：Win11 记事本 XAML 视图的 GetTextExt 矩形被标签栏高度带偏。修法：GUI 系统光标与 TSF 测量"共识"，明显不一致时系统光标否决 TSF；新增 `caret.tsf`/`caret.gui`/`caret.pick` trace 埋点 |
| 10 | **记事本"倒着输入"（上屏后光标跳回开头）** | `native/src/GyIme.cpp` | 根因：`CommitComposition` 只 SetText+EndComposition，从不设选区；XAML 宿主把选区恢复到组合串开头，下次上屏插到前面→整句倒序。修法：上屏后 `Collapse(TF_ANCHOR_END)` + `SetSelection` 钉到提交文字末尾（失败仅记 `commit.selection` trace 不影响上屏），3 个调用点补传 context。用户已验证：控制台/WT 切换 ✅、记事本候选窗位置 ✅、上屏顺序 ✅ |
| 11 | **组合中光标停在串头** | `native/src/GyIme.cpp` | 同源根因：`UpdateComposition` 的 SetText 后也未设选区，XAML 宿主把光标留在组合串开头。修法：每次更新组合串后同样钉选区到串尾（注意先测候选窗锚点再折叠，否则候选窗跑到串尾）。新增 `composition.selection` trace |
| 12 | **Kimi 候选窗再漂移（抓到现场）** | `native/src/GyIme.cpp` | 根因：切应用后首键 Chromium 布局竞态使 GetTextExt 失败，代码仍用本上下文从未验证过的旧矩形兜底显示。修法：本上下文未量到有效坐标前跳过显示（`caret.skip` trace），宁可晚一拍不错位。注意：Kimi 自 04:33 起运行旧代码，需重启 Kimi 或注销才加载新 DLL |

### 测试状态

- 构建目录：`gy输入法/native/build-trace`（`-DGY_IME_TRACE=ON -DGY_BUILD_HOST_SMOKE=ON`）
- `ctest -C Release -E GyInstallerSmoke` → **9/9 通过**（第 2 轮改动后复测仍 9/9）

### 部署状态

- `C:\Program Files\GYInput\versions\0.9.39\GyImeHost-0.9.39.exe` → 04:14 新版（含宽度中间值）
- `C:\Program Files\GYInput\tsf-0.9.39\GyIme.dll` → 05:31 已部署 v4 trace 版（含全部 12 项修复）；**下一步部署 `native\build\bin\Release\GyIme.dll` 正式版**（改名法，备份名 `.old5`）
- 注册表类别 → ✅ 已写入 5 个类别（`add-tip-categories.ps1`，未来安装包由修复 8 的代码自动注册）
- 注销后可清理：`tsf-0.9.39\GyIme.dll.old/.old2/.old3/.old4/.old5`、工作区 `apply-*.py` / `diag-tips.ps1` 临时脚本

---

## 二、第 2 轮部署与验证（免注销，约 5 分钟）

在**管理员 PowerShell** 依次执行：

```powershell
# 1. 注册缺失的 4 个 TSF 类别（修控制台/Windows Terminal 切不动，HKLM 写入）
powershell -ExecutionPolicy Bypass -File "C:\Users\Ethan\Desktop\01-Projects\shurufa\add-tip-categories.ps1"
# 预期输出：Registered categories for GY: 共 5 行（含 {13A016DF…} {25504FB4…} {49D2F9CE…} {364215D9…}）

# 2. 部署第 2 轮新 DLL（改名法：已加载的旧 DLL 可改名，新进程自动用新代码，不用注销）
Remove-Item "C:\Program Files\GYInput\tsf-0.9.39\GyIme.dll.old" -Force -ErrorAction SilentlyContinue
Rename-Item "C:\Program Files\GYInput\tsf-0.9.39\GyIme.dll" "GyIme.dll.old"
Copy-Item "C:\Users\Ethan\Desktop\01-Projects\shurufa\gy输入法\native\build-trace\bin\Release\GyIme.dll" "C:\Program Files\GYInput\tsf-0.9.39\GyIme.dll" -Force
```

验证清单（**必须开新窗口**，已运行的进程仍用旧代码）：

1. 重开记事本 → 打 `wo` → 候选窗应贴在文字下方（修复 9）；贴日志里的 `caret.tsf`/`caret.gui`/`caret.pick` 可确认走了哪条锚定路径
2. **新开** PowerShell → 点任务栏输入法图标选 GY → 打字出候选（修复 8）
3. Windows Terminal 里的 PowerShell：需**整体重启 Windows Terminal** 后再测（类别在激活时读取）
4. Kimi 里打字 → 候选窗位置应和之前一样正常（回归确认）
5. `xiayigeban` → 完整"下一个版本"（修复 3）；`wo` + ↓ 翻页（修复 4）

---

## 三、待办清单（按优先级）

### P0 — 收尾本轮
- [x] 第 2~4 轮部署验证通过：控制台/WT 切换 ✅、记事本位置/倒序/串头光标 ✅、Spotify ✅、Kimi 重启后新代码生效 ✅
- [x] trace 日志体检：核心链路全 hr=0；`composition.selection`×45 / `commit.selection`×16 全成功；`caret.skip`=0 次；仅 Host 自身进程内激活的 `selection-callback E_FAIL`×8（无用户影响，P3 可加进程内短路）；1 次修复前的 `composition.start E_INVALIDARG`（未再复现）
- [x] **换回正式版 DLL**：`native/build`（GY_VERSION=0.9.39，trace OFF）已编译 `build\bin\Release\GyIme.dll`（206336 字节，二进制无 trace 路径字符串），**待用户改名法部署**；部署后新进程即正式版，Kimi 等已开进程下次重启/注销自动切换
- [ ] Codex 打不了字的最终证据闭环（本轮最初问题）：修复 6/12 的漂移与上下文作废很可能已顺手治好，待用户在 Codex 里实测确认

### P1 — 引擎体验
- [ ] 学习词/自定义词进不了候选池：学习分只能重排已在 75 池内的候选，Rime 排名 96 之外的词永远不浮现（`PinyinEngine.cpp` Lookup）
- [ ] `Learn()` 的 `SettingsCache().Invalidate()` 无锁（理论竞态，后果轻微）

### P2 — 工程卫生
- [ ] 清理 `native/` 下约 50 个 `build-*` 残留目录 + 根目录临时文件（`test-write.txt`、`security-scan-temp-candidate.jsonl`）
- [ ] 清理安装目录备份：`C:\Program Files\GYInput\versions\0.9.39\*.bak/*.old`、`tsf-0.9.39\GyIme.dll.old`
- [ ] 源码行尾统一（LF/CRLF 混杂）+ `.gitattributes`
- [ ] 旧网页原型（`gy输入法/src`，含 AiAssistantPanel）归档到 legacy/

### P3 — 产品方向（需用户确认再动）
- [ ] 展开视图从 5×5 横排网格改为**竖排列表**（业界主流：搜狗/微信/微软拼音的更多候选都是竖排，宽度可再缩一半）——形态级改动，涉及键盘导航与点击映射，单独立项
- [ ] 本轮修复随下次正式发版走发布管线（release.json 升版本、签名、R2 上传）

---

## 四、常用命令速查

### 编译（Git Bash）
```bash
"/c/Program Files/CMake/bin/cmake.exe" --build "gy输入法/native/build-trace" --config Release
cd "gy输入法/native/build-trace" && "/c/Program Files/CMake/bin/ctest.exe" -C Release -E GyInstallerSmoke
```

### 部署 Host（可热更，单行）
```powershell
Remove-Item "C:\Program Files\GYInput\versions\0.9.39\GyImeHost-0.9.39.exe.old" -Force -ErrorAction SilentlyContinue; Rename-Item "C:\Program Files\GYInput\versions\0.9.39\GyImeHost-0.9.39.exe" "GyImeHost-0.9.39.exe.old"; Copy-Item "C:\Users\Ethan\Desktop\01-Projects\shurufa\gy输入法\native\build-trace\bin\Release\GyImeHost.exe" "C:\Program Files\GYInput\versions\0.9.39\GyImeHost-0.9.39.exe" -Force; Get-Process | Where-Object { $_.Name -like "GyImeHost*" } | Stop-Process -Force
```

### 部署 DLL（必须注销重登才生效）
```powershell
Remove-Item "C:\Program Files\GYInput\tsf-0.9.39\GyIme.dll.old" -Force -ErrorAction SilentlyContinue; Rename-Item "C:\Program Files\GYInput\tsf-0.9.39\GyIme.dll" "GyIme.dll.old"; Copy-Item "C:\Users\Ethan\Desktop\01-Projects\shurufa\gy输入法\native\build-trace\bin\Release\GyIme.dll" "C:\Program Files\GYInput\tsf-0.9.39\GyIme.dll" -Force
# 然后注销 Windows 重新登录
```

### 关键路径
- 源码：`C:\Users\Ethan\Desktop\01-Projects\shurufa\gy输入法\native\src\`
- 构建产物：`gy输入法\native\build-trace\bin\Release\`（GyIme.dll / GyImeHost.exe）
- 已安装 DLL：`C:\Program Files\GYInput\tsf-0.9.39\GyIme.dll`
- 已安装 Host：`C:\Program Files\GYInput\versions\0.9.39\GyImeHost-0.9.39.exe`
- trace 日志：`%TEMP%\GyIme.trace.log`（每行带 pid）
- 发布清单：`release\release.json`（当前 0.9.39 candidate）

---

## 五、给下一轮 Kimi 的提示

- 工作区根目录：`C:\Users\Ethan\Desktop\01-Projects\shurufa`
- 编辑器对混合行尾文件做多行 Edit 容易失败，**用单行锚点 Edit**
- 部署 Host 时用"改名优先"单行命令（运行中的 exe 可改名不可覆盖），避免用户打字时 Host 自动重启造成占用竞态
- 改 `CandidateWindow` 布局前注意文件里的 "Locked geometry / 产品契约" 注释，5×5 列数是契约，宽度可调
