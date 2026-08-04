# GY 学习语义跨平台契约

> 2026-08-05 随 Windows P1 修复落地。适用范围：Windows（已实现）、macOS（待对齐）、未来各端。
> 基线：`GY_INPUT_METHOD_PRODUCT_STANDARD.md` §3.1。本文件是它的实现层增补，不改动已锁定契约。

## 规则

1. **学习必须能"浮现"，不只是"重排"。** 用户真实选择过的词，无论其在引擎原始排名中的位置（哪怕在扫描窗口之外），下次输入相同编码时必须能进入候选池。只允许"池内重排"的实现视为 bug（Windows 曾犯：rank > 96 的学习词永远不出现）。
2. **学习词仍须过质量门槛。** 注入候选池前必须通过与引擎候选相同的可接受性检查（CJK 表意、长度上限），学习不是低质量内容的通行证。
3. **学习词必须遵守当前简繁模式。** 注入前按当前模式做脚本归一；繁体模式下不得出现简体学习词，反之亦然。
4. **排序规则：** 候选先按学习分降序稳定排序（同分保持引擎原序），自定义短语置顶，池上限 75。
5. **自定义短语与学习词同一体系。** 短语不绕过质量门槛和简繁归一；置顶是展示规则，不是豁免规则。
6. **学习数据跨设备共享走 Rime userdb 同步**（`sync_dir` + 各端 `installation_id`，双向 merge），不造私有格式。Windows 与 macOS 的用户学习目录分别是：
   - Windows: `%LOCALAPPDATA%\GYInput\rime`
   - macOS: `~/Library/Application Support/GYInput/rime`

## 各端实现状态

| 端 | 状态 | 位置 |
|---|---|---|
| Windows | ✅ 已实现（2026-08-05） | `native/src/PinyinEngine.cpp` `Lookup()`：学习分排序前注入缺失的学习词 |
| macOS | ⏳ 待对齐 | `macos/GYInput/Sources/GYInputController.m` + `GYSettingsStore.m`：自定义短语需过简繁归一与质量门槛；未来加候选治理层（75 池）时必须内建规则 1 |
| 跨设备同步 | ⏳ 未开始 | 两端 Rime 均支持 `RimeSyncUserData`；需各端补 sync 入口 + 选定 sync_dir 载体（Dropbox/iCloud/R2） |

## Mac 对齐时的注意点

- Mac 目前把 Rime 菜单原样透出，Rime 原生学习天然满足规则 1；**风险在于将来加 GY 候选治理层时把 Windows 的旧 bug 复制过去**。
- Mac 自定义短语（`GYSettingsStore.customPhrases`）当前无脑置顶且不转简繁，违反规则 3/5，对齐时一并修。
