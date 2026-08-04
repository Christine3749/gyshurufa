# GY 输入法 macOS 原生核心

本目录实现 [产品标准](../GY_INPUT_METHOD_PRODUCT_STANDARD.md) 的 macOS 适配层。它是
InputMethodKit 输入法，不复制 Windows TSF、注册表、命名管道或安装器。

## 当前能力

- 本地拼音候选与学习：无网络调用；只将用户实际选择的“拼音码 → 候选”偏好保存在本机。
- 简体／繁体／EN 三模式：单按 Shift 循环切换；模式由本地偏好保存并在应用切换后保持。
- EN 真直通：除模式切换键外，不拦截字母、数字、标点、Enter、Tab、删除、粘贴或应用快捷键。
- 系统候选窗兼容阶段：默认展示最多 5 个候选，`↓` 展开为最多 5 列 × 5 行；方向键、PageUp、PageDown、1–5 和鼠标可选词。
- 安全升级：输入源身份和 `inputText:key:modifiers:client:` 路由由构建门禁锁定；普通升级绝不改协议。

视觉语义以 [GY VI](../GY_VISUAL_IDENTITY.md) 为准。当前使用系统候选窗保障兼容；在自定义 GY 面板上线前，不改变候选数量、模式或选择语义。

## 本地验证

```bash
./macos/scripts/test-core.sh
./macos/scripts/package-core.sh
```

安装包后必须执行真实键盘验收：

```bash
./macos/scripts/smoke-test-core.sh
```

它会选择 GY 并打开 TextEdit；请用实体键盘输入 `nihao` + 空格，确认提交“你好”。脚本检查新产生的 `text-event` trace；自动化文字注入不能替代该测试。

## 发布边界

`release/release.json` 是跨端唯一版本真相。当前 macOS 包只是 `0.9.34` 候选实现；未完成 Developer ID 签名、公证、stapling 和真实键盘升级矩阵前，不能更新 manifest 中 macOS 的验证状态或公开发布。

完整的热升级事故、注销条件和回退要求见 [事故报告](INCIDENTS/2026-08-04-hot-upgrade-event-route.md)。
