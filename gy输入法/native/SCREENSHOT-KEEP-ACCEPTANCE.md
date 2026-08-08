# GY 输入法 × Keep：截图同步验收（0.10.66 candidate）

这份验收只验证 PNG 图片，不会清空既有文字剪贴板历史。目标是确认一张 Windows 截图能够经过可靠 outbox 写入 Keep，并在另一台已登录同一账户的设备上恢复为可粘贴图片。

## 前置条件

- 发送端与接收端都安装 `GYInputSetup-0.10.66.exe`，登录同一个 GY 账户。
- 两台设备的「通用」页中「跨设备剪贴板」和「即时粘贴」均开启（默认开启）。
- Keep 已部署包含图片路由的版本；图片单个上限为 10 MiB。

安装与本机健康检查：

```powershell
Start-Process -FilePath "C:\Users\Ethan\Desktop\01-Projects\shurufa\gy输入法\native\release\GYInputSetup-0.10.66.exe" -Verb RunAs -Wait
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\GYInput\Validate-GYInput.ps1"
```

## 两台 Windows 设备验收

1. 在发送端打开画图，画一个有明显颜色和文字的测试图；按 `Ctrl+A`、`Ctrl+C`。这会产生真实 Windows 位图剪贴板内容。
2. 在发送端打开 GY 设置的「剪贴板」页。应出现一张图片条目，先为“同步中”，Keep 确认后变为“已确认”。本机仍只显示 HEAD 的最多 20 条，不代表 outbox 只保存 20 条。
3. 打开 `https://keep.gyenbox.com`，刷新后确认出现相同的图片卡片。图片应可正常显示，而不是仅有文件名或占位文字。
4. 在接收端保持任意文本框或画图窗口可用，等待图片到达。开启“即时粘贴”时，GY 会把最新已确认图片写入接收端系统剪贴板。
5. 在接收端打开画图，按 `Ctrl+V`。验收通过条件是粘贴出原图，不是空白、文字“[图片]”或损坏图片。
6. 再复制一段不同文字，确认文字仍可跨设备同步；再重复一次图片步骤，确认第二张图片可以覆盖剪贴板并正常粘贴。

## 通过与失败判定

通过：发送端、Keep 卡片和接收端画图三处都是同一张实际图片，且接收端 `Ctrl+V` 可粘贴。

若失败，请保留以下信息后停止重复复制：发送端截图时间、Keep 是否出现图片卡片、接收端是否已有图片条目、以及本机健康检查输出。这样可以区分捕获、上传、Keep 存储、下载和写回系统剪贴板五个阶段。

## 本地自动回归覆盖范围

`GyClipboardHistorySyncSmoke` 已自动验证：离屏位图使用生产 GDI+ 路径编码为 PNG、PNG 签名正确、图片资产写入本地确认窗口后读回的字节完全一致。它不访问网络，也不会改动用户的真实系统剪贴板；网络与第二台设备的步骤必须按本页人工验收。
