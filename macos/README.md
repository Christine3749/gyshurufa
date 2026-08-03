# GY 输入法：最小启动核

这是一次从零开始的 InputMethodKit 重构，不是公开版本，也不含 Rime、候选窗、简繁／EN、Shift、设置、学习、网络或自动更新。

唯一的端到端验收：在 TextEdit 选择 GY 输入法后，输入 `nihao` 再按空格，必须提交 `你好`。其他字母按空格原样提交。

最小条件：

1. `.app` 有唯一的 bundle ID 和可选的 `.pinyin` 输入源。
2. 安装时调用 `GYInput --register-input-source`；正常服务启动绝不重新注册。
3. 服务仅创建一个 `IMKServer`。
4. 控制器只使用 InputMethodKit 的 `inputText:key:modifiers:client:` 文本事件入口。
5. 控制器只对活跃客户端设置 marked text 或插入 committed text；异常键永远交回目标 App。

## 构建与发布门禁

构建前，`./scripts/verify-input-source-contract.sh` 会锁定已经发布过的输入源身份：bundle ID、输入源 ID、`InputMethodConnectionName` 和控制器类名。它们不是普通配置；改变其中任一个都可能让旧用户看到“已选中 GY”，但按键永远到不了控制器。

```bash
./scripts/build-core.sh
./scripts/package-core.sh
```

安装新包后必须执行：

```bash
./scripts/smoke-test-core.sh
```

这个测试会选中 GY 并打开 TextEdit，但必须由测试者用**实体键盘**输入 `nihao` + 空格、确认提交“你好”。脚本随后检查新增的六条 `text-event` 日志。自动化注入文字不能替代此测试，因为它可能绕过 macOS 到 InputMethodKit 的真实按键路由。若发布包含事件入口或输入源身份迁移，必须另行完成注销登录后的升级矩阵测试。

完整事故记录、升级兼容性契约与支持排障流程见 [INCIDENTS/2026-08-04-hot-upgrade-event-route.md](INCIDENTS/2026-08-04-hot-upgrade-event-route.md)。
