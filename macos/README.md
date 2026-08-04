# GY 输入法 macOS 原生核心

本目录是 [GY 产品标准](../GY_INPUT_METHOD_PRODUCT_STANDARD.md) 的 macOS 外壳：键盘接入使用 InputMethodKit；拼音解析、候选质量、简繁转换和学习使用与 Windows 相同的 Rime schema 与 `native/runtime/rime/shared` 数据。

## 共同输入体验

- `gy_pinyin` 是 Windows 与 macOS 共同的输入 schema；词库、拼写规则、标点和 OpenCC 简繁规则不在 Mac 端另造一套。
- Bundle 图标由 Windows 的唯一源文件 `native/installer/assets/gy-tray-icon.svg` 生成；深墨黑背景和白色 GY 标准字不在 Mac 端重绘。
- 简体／繁体／EN 三模式由 GY 保存；EN 除切换键外完全直通应用。
- Rime 用户学习仅落在本机 `~/Library/Application Support/GYInput/rime`；输入路径不联网、不读取剪贴板。
- 当前候选 UI 是原生 GY 面板：默认最多 5 个，`↓` 展开最多 5×5，支持方向键、分页、1–5 和鼠标选词；颜色、箭头和模式顺序与 Windows 共用 VI。

## 构建与测试

构建脚本从固定版本的 Rime、Boost 源码构建 arm64 macOS 13 运行库，并把 `librime`、OpenCC 数据和共享 Rime 数据复制到 app bundle。它不链接 Homebrew 动态库；最终用户不需要 Homebrew。

```bash
./macos/scripts/test-core.sh
./macos/scripts/package-core.sh
```

候选窗的视觉验收无需安装输入法：先构建，再运行
`./macos/scripts/preview-candidate-panel.sh collapsed` 或 `expanded`。预览不会注册、选择或覆盖系统输入源。

安装候选包后必须运行实体键盘门禁：

```bash
./macos/scripts/smoke-test-core.sh
```

它会打开 TextEdit；请用实体键盘输入 `nihao` + 空格，确认提交“你好”。升级、注销条件与回退规则见 [事故报告](INCIDENTS/2026-08-04-hot-upgrade-event-route.md)。

升级后先运行 `GYRecovery.sh status`。状态为 `logout-required` 时，不会假装新核心已启用：保存工作、注销再登录、通过实体键盘门禁后，以 `sudo GYRecovery.sh mark-known-good` 标记为下一次的安全回退基线。`repair` 只重建 GY 注册；`rollback` 只恢复该基线，不触碰其他输入法或系统缓存。

## 发布边界

`release/release.json` 是跨端唯一版本真相。当前仍是 `1.0.9` 候选：未完成实体键盘升级矩阵、Developer ID 签名、公证与 stapling 前，不能改为公开发布。
