# GY 输入法 macOS 端修复与契约对齐 — 交接文档（带回 Windows 端合并）

> 日期：2026-08-05 · Mac 端 Kimi 施工完成 · 对应 Windows 0.9.39+ 契约（WINDOWS-DESIGN.md / SETTINGS-PANEL-DESIGN.md）
> 工作区：`gy输入法/macos/`（InputMethodKit + librime，Obj-C++，arm64）

---

## 一、最终状态

- 构建签名通过，安装于 `/Library/Input Methods/GYInput.app`（唯一副本）
- 系统注册：TIS 登记 1 条、启用 1 条（父项 + `.pinyin` 输入模式）
- 菜单栏显示「输入法.网」+ 灰底 GY 图标（macOS systemGray `#8E8E93`，22.37% 圆角）
- 实测通过：拼音组词、5 候选条、↓ 展开 5×5 网格、网格内方向键自由走位、数字选词（含行相对）、Shift 中⇄EN 循环、双窗问题、设置面板四页

## 二、本轮修复清单（按时间序）

### 1. 构建系统（scripts/build-core.sh）
- 清理上一轮中断写坏的重复 clang++ 命令段（曾导致 5 个源文件未链接）
- 新增打包步骤：`Resources/rime-data/`（**此前完全缺失，是"打不出字"的根因**）、`AppIcon.icns`、`*.lproj` 本地化
- 新增 `scripts/render-app-icon.py`：从锁定 SVG 字标逐路径渲染全套 iconset（PIL 贝塞尔采样，4x 超采样）

### 2. Rime 桥接层（GYRimeBridge.h/.mm）
- 新增 `candidatesUpToCount:`：跨页收集候选（上限 75），收集后恢复原页
- 新增**候选治理管线**（WINDOWS-DESIGN §6）：纯 CJK 表意文字、≤12 字、过滤表情/私用区/符号、去重
- 新增 `commitCandidateAtAbsoluteIndex:` + **过滤序号→Rime 原始序号映射表**（`_candidateIndexMap`）
  - ⚠️ 这是关键 bug：过滤/去重后显示序号 ≠ Rime 内部序号，直接提交会选错词并被学习加权（用户实测出现 祢蚝/妮恏 置顶）
- P0-1 整句选词保留剩余拼音（`remainingCompositionInput`，只保留 a-z）——Windows 端静态修复，已编译验证

### 3. 自绘候选窗（新增 GYCandidateWindow.h/.m）
- 逐行移植 Windows `CandidateWindow.cpp` 视觉契约：
  - 收起态：5 候选 → `˅`（锚点锁定左下 8/8）→ 细分隔线 → 简/繁/EN
  - 展开态：固定 5 列 × ≤5 行（75 池 3 页，显示 页码/总页数）
  - 格宽两遍式 `clamp(自然宽度, 82, 110)`；四字词必完整；三套主题色板（蓝夜/暖白/石墨）+ `#5280E2` 箭头
  - 贴光标定位、触屏底自动上翻、非激活 NSPanel、模式小窗 700ms 自动消失
- 鼠标：点候选提交、点箭头展开/收起、点模式标打开设置、展开态翻页器

### 4. 控制器（GYInputController.m）按键契约（§4 全表）
- 收起态：Space=首选、Enter=原样拼音、←→↑ 透传、↓ 展开、1–5 选第 N
- 展开态：Space/Enter=高亮项、方向键网格走位（页底跨页同列、短行不虚选）、↑ 首页首行收回、1–5=高亮行第 N 列
- PageUp/PageDown 一律翻 25/页（引擎翻页作池外兜底）
- **Shift 单按循环 中⇄EN**（按下松开无中间键才触发；切 EN 取消预编辑不上屏；记 lastChineseMode）
- **方向键 Function 修饰符豁免**（macOS 给方向键自动带 Function flag，旧代码一律透传导致导航全失效——这是 macOS 端特有坑，Windows 端如遇类似问题可参考）
- `deactivateServer:` 失焦收窗（IMK 每个客户端会话一个控制器实例，不收窗会"一屏两个候选窗"）
- P0-3 组合中标点：提交首选+中文标点

### 5. 设置面板（GYPreferencesController.m 全量重写，SETTINGS-PANEL-DESIGN）
- 520×680 固定窗、圆角 14、四页导航（通用/输入/外观/账户）、页眉页脚文案逐字
- 主题卡片点击即整窗换色（palette 三主题数值与 §8 一致）；字号契约改 13/15/17（旧"标准 16"自动迁移 15）
- 短语编辑器 `编码=短语1|短语2` 与 Windows 互通；导入限 64KB + 导入前自动备份
- "完成才保留 / × 弹确认并按快照回滚"
- ⚠️ macOS 特有坑：root view `isFlipped` 不会传导给子视图容器，内容容器和卡片必须各自翻，否则整页内容倒置沉底

### 6. 品牌
- 名称：`输入法.网`（CFBundleName/CFBundleDisplayName + **InfoPlist.strings 三语**——菜单栏输入法菜单的模式名只读 InfoPlist.strings，不配就显示原始 ID）
- 图标：GY 白字标 + systemGray 底（⚠️ 偏离 VI 文档"深墨黑底"条款，系产品决策，建议回写契约）
- Bundle ID / 连接名 / 输入源 ID 全部未动（identity 契约锁）

### 7. 系统环境清理（一次性，非代码）
- LaunchServices 残留登记注销：`github-gyshurufa/macos/build/` 下 1 个 GYInput + 10 个 preview（2.0.0–2.0.8）——**这些残留是 GYInputPreview 反复崩溃重启的来源**
- `com.apple.inputsources.plist` 补写 `.pinyin` 输入模式启用条目（清理时误伤，菜单只显示 Input Mode 条目，仅有父项不显示）
- 缓存刷新链：tiswitcher.cache / TextInputMenuAgent / SystemUIServer / cfprefsd / iconservices*

## 三、macOS 端已知差异（契约允许）
- 设置窗为输入法内嵌窗口（非独立 Settings.app）
- 学习由 Rime userdb 原生承担（§11.4 允许的"原生学习直通"），清空学习 = userdb 移入回收站
- 凭据/账户 v1 仅本地标识文本，无密码框

## 四、建议回写 Windows 端/上位契约的事项
1. VI 文档图标条款增加"macOS 菜单栏图标可用 systemGray 底"的平台例外
2. 候选治理管线的**索引映射**问题在 Windows 端不存在（Host 一次性取全量后治理），但若未来改分页拉取需注意
3. `gy输入法---品牌-logo-规范` 目录建议补充 `InfoPlist.strings` 模式名规范（跨端名称一致性）

## 五、验收清单（用户已实测通过）
- [x] nihao+空格=你好；xiayigeban 选词后剩余拼音保留
- [x] 组合中标点=首选+中文标点
- [x] ↓ 展开 5×5；网格内 ←→↑↓ 自由走位；跨页同列；短行不误选
- [x] 数字 1–5 收起选第 N / 展开选高亮行第 N 列（选词精确不错位）
- [x] Shift 单按中⇄EN 循环
- [x] 切换应用候选窗自动关闭（不再一屏两窗）
- [x] 设置面板四页排版、主题联动换色、完成/× 保存语义
- [x] 菜单栏「输入法.网」+ 灰底 GY 图标；系统输入法列表仅 1 条
