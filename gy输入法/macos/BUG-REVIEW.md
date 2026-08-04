# GY macOS 版代码审查：Bug 清单与分层差距

> 2026-08-05 由 Kimi 在 Windows 端静态审查产出。源码共 658 行（8 个源文件）。
> 审查基线：`GY_INPUT_METHOD_PRODUCT_STANDARD.md`、`macos/M1_ROADMAP.md`、Windows 三层架构（TSF 核心不动层 / Host 可演进层 / 会员服务层）。
> 注意：以下结论未经真机验证；编译与行为确认仍需在 Apple Silicon Mac 上跑 `scripts/build-macos.sh` + 冒烟。

---

## 一、P0 功能性 Bug（直接影响打字正确性）

### 1. 整句输入选词后丢失剩余拼音 ⚠️ 最严重
- 位置：`GYInputController.m:199-207`（`commitText:`）+ `GYRimeBridge.mm:157-169`
- 现象：整句输入如 `xiayigeban`，Rime 的 `select_candidate_on_current_page` 可能只提交"下一"、剩余 `yigeban` 仍在 Rime composition 里；但控制器**无条件** `clearComposition` + 清空 `_composition` + 隐藏候选窗，剩余拼音被静默吞掉。
- 修法：`commitCandidateAtIndex` 返回提交文本后，立刻 `get_context` 检查 Rime 是否仍有未完成 composition；有则把剩余 input 写回 `_composition`、刷新候选和 marked text，而不是清空。

### 2. 5×5 展开网格与方向键导航完全缺失
- 位置：`GYInputController.m:111-197`（`handleEvent:` 无任何方向键分支）
- 现象：`↓` 落到 `GYInputController.m:190` 的字母判断后 `return NO`，直接透传给应用——契约要求的"首次按 ↓ 展开网格"不存在；`← → ↑ ↓` 网格移动、展开态 Enter/Space 提交高亮、展开态数字键按行选列，全部没有。
- 契约：`GY_INPUT_METHOD_PRODUCT_STANDARD.md §3.3` 明确这是 **Windows × macOS 共同规则**，"两端禁止按底层实现差异改变这套键盘契约"。
- `GYSettingsStore.showExpandedCandidates`（`GYSettingsStore.m:6,40,64`）是死代码，无人读取。

### 3. 组合中的标点穿透到应用
- 位置：`GYInputController.m:180-187`（标点转换只在 `_composition.length == 0` 时生效）
- 现象：打着拼音按 `,` `.` `?` 等，走到 `handleEvent:` 末尾 `return NO`——应用收到原始 ASCII 按键而 marked text 还挂着，多数应用会把拼音原文上屏再插 ASCII 标点，行为不可预期。
- 修法：组合中按标点应先提交首选候选（或按契约取消），再输出中文标点。

---

## 二、P1 与产品标准/设置系统脱节

### 4. `candidatePageSize` 设置从不生效
- `GYSettingsStore.m:62-63` 定义了 5-9 的页大小，`GYPreferencesController` 却没暴露它，bridge 也从未把它传给 Rime（Rime 的 `menu/page_size` 在 schema 里，bridge 没有覆盖逻辑）。死设置。

### 5. 自定义短语不遵守简繁模式
- 位置：`GYSettingsStore.m:74-80` + `GYInputController.m:65-75`
- 繁体模式下自定义短语按原文插到候选第 0 位，违反标准 §3.1"用户词库和常用短语优先，但仍须遵守当前简繁模式"；且无条件置顶，凌驾于学习排序之上，无质量门槛。

### 6. 用户 Rime workspace 永不更新（升级即陈旧）
- 位置：`GYRimeBridge.mm:22` —— 只要用户目录里存在 `luna_pinyin.schema.yaml` 就 `return YES`
- 后果：app 升级带来新词典/新 schema 后，老用户永远跑第一版的 build。需要版本戳（如比较 `distribution_version` 或写 `.deployed-version` 文件）决定重部署。

### 7. 候选面板跨应用残留风险
- 没有 override `deactivateServer:` / `activateServer:` / `inputControllerWillClose` 之外的隐藏逻辑（`inputControllerWillClose` 有，但切换 app 不一定触发 close）。这正是 Windows 端刚修掉的"候选窗漂移"问题的 Mac 对应面，需在会话失焦时显式 `hide`。

### 8. 设置弹窗焦点与布局问题
- 位置：`GYPreferencesController.m:14-57`
- IM 进程是后台 agent，`[alert runModal]` 前没有 `[NSApp activateIgnoringOtherApps:YES]`——设置窗可能藏在其他窗口后面、拿不到焦点。
- `NSStackView` 走 Auto Layout 却又手写 `stack.frame = NSMakeRect(0,0,360,180)`，两个 `NSTextField` 无宽度约束，可能塌成不可用的窄条。按 M2 验收，设置本来就该是独立小 app，NSAlert 只是占位——建议直接跳过修这个占位 UI，立项独立 Settings app。

### 9. `candidateSelected:` 用文本反查索引
- 位置：`GYInputController.m:104`（`indexOfObject:text`）
- 候选重复时选中的永远是第一个同文本项；IMK 的回调本应配合 `candidateStringIdentifier:` 用稳定标识。轻。

---

## 三、P2 工程卫生

| # | 位置 | 问题 |
|---|------|------|
| 10 | `GYRimeBridge.mm:77` | `distribution_version = "0.9.15"` 硬编码，违反标准 §7"版本唯一真相是 release.json" |
| 11 | `GYRimeBridge.mm:62-69` | 嵌套重复 `#if GY_HAS_RIME`（能编译，纯脏） |
| 12 | `GYRimeBridge.mm` 全文件 | 从不调用 `api->finalize()`；长驻进程退出时 Rime 无清理 |
| 13 | `GYRimeBridge.mm:125-138` | 每个按键都 `clear_composition` + 全量重放整个拼音串，O(n²)；功能正确但应增量喂键 |
| 14 | `GYInput.entitlements` | 空 plist。直装版可以，但未来同步/共享组/Sandbox 要提前规划 |
| 15 | `GYInputController.m:63` | 嵌套 `#if` 同款问题在 bridge init 里还有一处（63 行重复 `#if GY_HAS_RIME`） |

---

## 四、对照 Windows 三层架构的 Mac 分层差距

Windows 已确认的三层：

```text
① 最小不动层  TSF DLL：键盘接入、模式、预编辑、提交、与 Host 通讯
② 可演进层    Host：候选质量、词库、学习、设置、界面
③ 会员层      独立服务：账户、同步、AI（输入路径零调用）
```

Mac 现状：**①②糊在一起，③不存在**。

| 层 | Mac 现状 | 差距 |
|---|---|---|
| ① 核心不动 | `GYInputController` + `GYRimeBridge` | 控制器里写了"可演进层"逻辑：自定义短语注入排序（`commitDisplayedCandidateAtIndex`）、标点转换表、候选拼装——这些规则每改一次都要动核心进程 |
| ② 可演进 | 无独立载体 | 候选治理（75 池、质量门槛、学习注入、简繁过滤）、设置 UI 都没有独立模块/进程；设置只是一个 NSAlert 占位 |
| ③ 会员层 | 无 | M1_ROADMAP 自己规定 "Account / AI / sync: separate process/service, not callable during composition"，未建 |

建议的 Mac 三层映射（与 Windows 语义对齐、但用 macOS 原生形态）：

```text
① GYInput.app（IMK 核心，尽量冻结）
   GYInputController：按键语义、模式、marked text、IMK 候选窗
   GYRimeBridge：唯一碰 librime 的边界（已是好设计，保持）
② GYEngine / GYSettings（可演进，模块或 XPC 服务）
   候选治理：75 池、质量门槛、学习注入、简繁过滤、自定义短语
   独立 Settings.app：模式、候选外观、短语、学习数据管理（M2 要求）
③ GYAgent（会员层，独立进程/XPC，未建）
   账户、跨设备 Rime userdb 同步、未来蒸馏 AI 推理服务
   输入路径零调用
```

IMK 是单进程模型，不一定需要 Windows 那样的独立 Host **进程**，但模块边界必须现在就划清：候选治理从 controller 抽出去，是修 P0/P1 时顺手该做的事。

---

## 五、建议修复顺序

1. **P0-1 整句丢拼音**（行数少、收益最大，且 Windows 刚修过同类问题有参照）
2. **P0-3 组合中标点**（小改动）
3. **P1-6 workspace 版本戳**（不修则下次发版老用户全陈旧）
4. **P0-2 展开网格**（契约级缺失，工作量大，单独立项，和 Windows 端"竖排列表"方向决策一起做）
5. P1 其余 + 候选治理抽出 controller（分层重构第一步）
6. P2 随手清
