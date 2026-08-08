# GY 输入法 macOS 2.1：VI、交互与 Keep 信息流实施规范

> 状态：Mac 端唯一施工稿
>
> 日期：2026-08-08
>
> 目标：macOS 2.1「Keep First」
>
> 范围：gy输入法/macos、与 Keep 的已定义 API 契约
> 不在范围：Windows TSF、Rime 词典内容、会员收费、共享账户正式上线

---

## 1. 产品结论

一句话：**Keep 是唯一权威信息时间线；输入法是 Keep 最新可粘贴信息流的快速视图和输入出口。**

~~~text
复制文字 / 截图 / 复制文件
        │
        ├─ 系统剪贴板：立即可 ⌘V，永不等网络
        ├─ 本地可靠 Outbox：不限 20 条
        └─ Keep：ACK 后成为账号的权威顺序
                      │
                      ├─ Mac / Windows / Linux：HEAD 20 快速粘贴
                      ├─ Keep Web：完整 GY 信息流
                      └─ iOS：用户主动拉取后粘贴
~~~

### 三条锁定原则

1. **20 条是视图上限，不是存储上限。** Outbox 与 Keep 历史不能因为第 21 条出现被删除。
2. **复制是唯一吸收入口。** Keep 不做第二个复杂录入入口；普通手写 Keep 笔记不进入输入法的 20 条。
3. **自动吸收不等于无差别上传。** 密码、验证码、私钥、助记词、银行卡号默认仅本机；正文、图片和 token 不得写入日志。

### 版本边界

| 信息块 | macOS 2.1 | 后续版本 |
|---|---|---|
| 文字 | 捕获、持久化、ACK、增量、跨端、回写剪贴板 | 富文本 / HTML |
| 图片 | PNG 截图、缩略图、哈希、上传、下载、跨端 | HEIC、编辑、动态图 |
| 文档 | 识别类型与顺序；无对象 API 时明确仅本机 | PDF、Office 预览 |
| 文件 | 识别类型与顺序；无对象 API 时明确仅本机 | 分块上传、断点续传、分享 |

不能把“已识别”写成“已同步”。第一版的真实闭环是：文字和 PNG 截图在 Mac、Windows 与 Keep Web 三端可见、可恢复、可验证。

---

## 2. 现有实现与上线前提

### 2.1 Mac 已有基础，保留而非推倒重来

| 模块 | 当前作用 | 2.1 要求 |
|---|---|---|
| GYAccountAuth | 原生邮箱密码登录，Keychain 保存 refresh token | 保留，补足状态和错误呈现 |
| GYClipboardHistory | 0.2 秒 changeCount 捕获、延迟供给重试、自写指纹抑制 | 扩展为带类型的信息块 |
| GYKeepSync | 文字上传 + 3 秒拉取的旧模型 | 替换为 Outbox、ACK、cursor 增量 |
| GYPreferencesController | 五页设置、账户与剪贴板页 | 按本规范完成正式交互 |
| GYCandidateWindow | AppKit 原生候选窗、三主题、5 列布局 | 锁定 5×5 候选与回退补位 |

### 2.2 Keep 服务端必须先真正上线

Mac 应接的 v4 同步协议已在 GyenBox 分支：

~~~text
codex/keep-sync-cursor-01062
~~~

其中有每账户单调 sequence、ACK、cursor、DELETE、设备身份、SSE 和图片 GCS 上传。它不是因为存在于一个分支就自动可用。

Mac 接入之前，Keep 负责人必须逐项完成：

- 合并该分支到 main；
- 执行 Prisma migration；
- 部署 apps/keep 到 keep.gyenbox.com；
- 用真实 Bearer token 探测 snapshot 端点得到 200；
- 留下部署 revision、迁移 revision、上一版回滚点。

未完成时，Mac 只能运行现有兼容同步，不能宣称“极致同步已上线”。

---

## 3. 架构和线程红线

~~~mermaid
flowchart LR
  P["macOS General Pasteboard"] --> C["GYClipboardCapture / changeCount 0.2s"]
  C --> S["GYBlockStore / SQLite + blob"]
  S --> H["HEAD 20 projection"]
  S --> O["Reliable Outbox"]
  O --> K["GYKeepSync / private serial queue"]
  K --> R["Keep ACK / cursor / SSE"]
  R --> A["GYRemoteEventApplier"]
  A --> S
  H --> U["设置页、历史面板"]
  I["GYInputController / Rime / Candidate"] -. "禁止等待 HTTP" .-> K
~~~

### 硬规则

- Rime、候选窗、按键提交、输入法主路径零网络、零远端等待。
- 复制捕获只做本地持久化；HTTP 永远在同步私有串行队列。
- 单次只有一个同步回合；UI 一律回主线程。
- 当前版本不创建第二个可见的 GY Link.app。先保留在输入法应用内的后台服务；未来需要输入法未激活仍常驻时，另立 LaunchAgent/XPC 项目。

### 本地文件和数据模型

~~~text
~/Library/Application Support/GYInput/
  sync.sqlite                  # 同步事实，WAL
  blobs/<entryId>.png          # 未确认或已下载的图片
  settings.json                # 非敏感设置
  rime/                        # Rime 学习数据
~~~

禁止继续把 clipboard-history.tsv 当作可靠 Outbox。旧 TSV 可以一次性迁移，迁移成功后只保留只读备份。

| 表 | 最小字段 | 用途 |
|---|---|---|
| blocks | entry_id PK、kind、captured_at、state、sequence、origin_device_id、preview、sha256、blob_path | 每一信息块的本地事实 |
| outbox | entry_id PK、attempts、next_retry_at、last_error | 不受 20 条限制的可靠队列 |
| sync_state | account_id、cursor、device_id、snapshot_version | 每个账号的同步进度 |
| tombstones | entry_id、sequence | 删除事件去重 |

公共块字段：

~~~text
entryId
kind: text | image | document | file
capturedAt
state: captured | queued | uploading | confirmed | offline |
       retry_wait | local_only | rejected | deleted
sequence?                 # 只由 Keep 返回
originDeviceId?
preview
byteSize?
sha256?
localBlobPath?
sensitivity
retryCount / lastErrorCode
~~~

所有 sequence 用十进制字符串保存，不能使用会失去 64 位精度的浮点数。capturedAt 只用于展示和审计，绝不能取代 server sequence 作为多设备排序。

### HEAD 20 的唯一公式

~~~text
HEAD 20 =
  最近本机未确认块（按捕获顺序）
  + Keep 已确认 GY 信息块（按 server sequence 倒序补足）
~~~

卡片以 entryId 身份做 diff。ACK 到达时卡片原地从“同步中”变为“已确认”；若另一设备先写入，卡片按 server sequence 平滑移动。禁止整表替换、白屏或闪烁。

---

## 4. VI：统一视觉基线

### 4.1 气质与颜色

- 高级、克制、工程感；深色石墨为默认。
- 不用大面积渐变、霓虹光晕、卡通图标或营销语言。
- 同步状态低调但可辨认；中文用 PingFang SC / 系统字体，技术字段可用 SF Mono。

| token | GY 蓝夜 | 暖白 | 石墨 |
|---|---|---|---|
| ink | #101216 | #F3F1EB | #15171C |
| surface | #1D2128 | #FCFBF8 | #1E2128 |
| surfaceHover | #23272F | #EAE7E0 | #242830 |
| border | #343A45 | #D0CBC1 | #363B46 |
| text | #FAFAFB | #1A1B1E | #F4F5F7 |
| muted | #9BA3B3 | #7A7871 | #949AA8 |
| accent | #2B60DD | #2B60DD | #2B60DD |
| warning | #C9912F | #A86D17 | #C9912F |
| danger | #D35C5C | #B94343 | #D35C5C |

同步中为低饱和蓝；已确认只用 muted；离线/重试为 warning；需要处理才用 danger；敏感仅本机显示锁与 muted，不制造恐慌。

### 4.2 设置窗口

- 固定 520 × 680 pt，圆角 14，1 pt border，无系统标题栏。
- 字标 52 × 33；标题“输入法设置”17 pt semibold；副标题“基础输入始终离线可用”10 pt。
- 导航左 18、宽 72、首项 y=118、47 pt 间距；选中态右侧 7 pt 蓝线。
- 内容区 x=112、宽 384；底部“完成”110 × 42。
- 页面顺序固定：通用 · 输入 · 外观 · 账户 · 剪贴板。
- 所有 AppKit 子 view 显式统一 flipped 坐标；父 view 的 isFlipped 不会继承。

---

## 5. 候选窗与输入交互

### 5.1 固定几何

- 收起态：5 个候选 + 分隔线 + 展开箭头 + 简/繁/EN。
- 展开态：5 列 × 5 行 = 25 个候选一页；扫描上限 96，最多三页。
- 候选宽度取自然内容，限制 82–110 pt；字号 13、15、17。
- 外框圆角 9、选中项圆角 6；选中蓝 #2863EB；箭头 #5280E2。
- 必须是 non-activating NSPanel，贴文本 caret；底部不足时翻到 caret 上方。

### 5.2 5×5 补位是锁定产品规则

用户不接受候选窗因为精确拼音结果少就缩成一两个候选。规则：

1. 先取精确编码的合格候选；
2. 少于 25 时，用逐级放宽编码补位，例如 gei → ge；
3. 仍不足时继续按定义好的回退阶梯补充真实候选；
4. 所有补位项必须真实、可提交、可学习；不得重复、空白或伪造占位；
5. 每项有 commitKind：
   - rime：保留原 Rime index，按 Rime 选择；
   - directFallback：直接提交文字，清理当前 composition，并按本地学习语义记录；
6. 所有精确项与补位项均经过纯 CJK、≤12 字、无 emoji/私用区/符号、去重门槛。

因此 gei 的第一项可以是“给”，后面以 ge 的真实候选补齐；不能出现“只显示一个给”，也不能用“给”重复填满 25 格。

### 5.3 键盘契约

| 输入 | 收起态 | 展开态 |
|---|---|---|
| a–z / ' | 更新拼音与候选 | 同左 |
| Space | 提交首选 | 提交高亮 |
| Enter | 原样提交 ASCII 拼音 | 提交高亮 |
| 1–5 | 提交第 N 项 | 提交高亮行第 N 列 |
| ↓ | 展开 | 向下；页底同列跨页 |
| ↑ | 透传 | 向上；首页顶行再按收起 |
| ← / → | 透传 | 横向移动，边界跨页 |
| PageUp / PageDown | 翻 25 项页 | 同左 |
| Esc | 取消组合 | 取消组合 |
| 单按 Shift | 中文 ⇄ EN | 同左 |
| Ctrl / Alt / ⌘ 组合 | 透传 | 透传 |

- EN 彻底直出，不组拼音、不弹候选、不截获快捷键。
- 切 EN 时取消未确认拼音，绝不偷偷上屏。
- 失焦或输入上下文切换必须隐藏旧候选窗，杜绝幽灵候选窗。

---

## 6. 设置页交互

### 通用

- 常用短语：code=短语1|短语2；
- 清空学习、导出、导入；导入最大 64 KB，先自动备份；
- 跨设备剪贴板开关；
- 即时粘贴开关。

默认：跨设备剪贴板开启。即时粘贴仅对用户自己的受信任设备组开启；共享来源默认只进入信息流，不覆盖系统 clipboard。

### 输入与外观

- 简体/繁体/EN 三段选择器，点击即生效；
- GY 蓝夜、暖白、石墨；紧凑/默认/大字号；
- AI 外观预览助手仅做无网络预览占位，不能修改 Logo、候选箭头、5×5 布局和输入规则。

### 账户：原生登录，不跳网页

账户页两张卡：

1. 账号/本地标识：仅本机文本，不影响 GY 登录。
2. GY 账户：
   - 未登录：邮箱、密码、登录；
   - 登录中：按钮禁用，显示“登录中…”；
   - 已登录：邮箱、同步状态、退出登录；
   - 失败：给可理解错误，不显示 HTTP、token、密码。

登录：

~~~http
POST https://gsyen-api-776196228503.asia-east1.run.app/api/auth/login
Content-Type: application/json

{ "email": "...", "password": "..." }
~~~

成功数据包含 access_token、refresh_token、expires_at、user。

- refresh token 仅存 Keychain：service 为 wang.shurufa.GYInput.gsyen，account 为 session，AfterFirstUnlockThisDeviceOnly；
- 密码永不持久化；access token 仅内存；
- 用现有 /api/auth/me 恢复会话；只有 401 清 Keychain，网络失败等待下次重试；
- 登录后调用 GYKeepSync 的 accountDidChange，切换账号不得把前一账号远端头部写进当前系统 clipboard。

### 剪贴板页

它是“最近可粘贴 GY 信息流”，不是第二个 Keep 编辑器。

- 顶部右侧：清理。确认文案：“从 Keep 删除当前 20 条 GY 信息块？普通 Keep 笔记不会受影响。”
- 清理仅删除 source=gy-clipboard，写 DELETE 事件；其他设备同步更新。更旧的 GY 块补位是正确行为。
- 每张卡：文字 preview 或图片缩略图、时间、来源设备、状态。
- 点击卡片：写入系统 clipboard 且带 entry marker；不创建新的 Keep 条目。
- 右键：复制、从 Keep 删除、仅在本机隐藏；破坏性动作都需清晰文案。
- 没有“一键保存到 Keep”，因为复制已经自动吸收。

---

## 7. Keep v4 协议（Mac 必须严格对齐）

### 7.1 所有请求

~~~http
Authorization: Bearer <access_token>
Accept: application/json
X-GY-Device-ID: <stable-url-safe-id>
X-GY-Device-Name: <MacBook Pro>
~~~

设备 ID 第一次登录生成，存 Keychain/同步库，不能随每次启动变化。sequence 由服务端按 owner 分配，客户端绝不拿 capturedAt 当最终排序。

### 7.2 文字提交：一跳 ACK

~~~http
POST https://keep.gyenbox.com/api/clipboard/sync
Content-Type: application/json

{
  "id": "entryId",
  "textBase64": "UTF-8 Base64",
  "capturedAt": 1760000000000
}
~~~

~~~json
{
  "ok": true,
  "data": {
    "ack": { "id": "entryId", "sequence": "42" },
    "cursor": "42"
  }
}
~~~

收到 ACK 必须用一个本地事务完成：

1. blocks.sequence = ACK.sequence；
2. blocks.state = confirmed；
3. 删除 outbox 行；
4. sync_state.cursor 取最大值；
5. UI 只更新这个 entryId。

同 ID 重试必须幂等，不得双写。

### 7.3 图片提交：PNG、哈希、GCS

~~~http
PUT https://keep.gyenbox.com/api/clipboard/images/{entryId}?format=ack-v3
Content-Type: image/png
X-GY-Captured-At: 1760000000000
X-GY-SHA256: <64 位小写 hex>

<原始 PNG 字节>
~~~

- 最大 10 MiB；超限显示“图片过大，仅本机”，不可默默丢弃；
- 优先读取 NSPasteboardTypePNG，TIFF 后台转 PNG；
- 对 PNG 算 SHA-256；本地 blob 一直保留到 ACK；
- 服务端 ACK 后才标 confirmed；
- 收到图片事件后，按需 GET /api/clipboard/images/{entryId}，再校验 MIME、大小、SHA-256；
- 写回系统 clipboard 时优先写 NSPasteboardTypePNG，不能降级为 [图片] 文字。

### 7.4 Snapshot 与 cursor 增量

首次登录、cursor 丢失、本地库重建：

~~~http
GET /api/clipboard/sync?snapshot=1&format=wire-v4
~~~

日常：

~~~http
GET /api/clipboard/sync?cursor=<decimal>&format=wire-v4
~~~

响应：

~~~json
{ "ok": true, "data": { "cursor": "42", "hasMore": false, "payload": "<base64 wire>" } }
~~~

base64 解码每行：

| 类型 | wire-v4 |
|---|---|
| 文字 ADD | T	tab sequence	tab id	tab capturedAtMs	tab textBase64	tab originDeviceId |
| 图片 ADD | I	tab sequence	tab id	tab capturedAtMs	tab mime	tab size	tab sha256	tab originDeviceId |
| DELETE | D	tab sequence	tab id	tab originDeviceId |

处理规则：

- 严格 sequence 升序应用；一页成功才提交 cursor；
- hasMore 为 true 时继续取下一页；
- DELETE 是墓碑，移除本地块与 HEAD；保留已见 sequence 去重；
- 删除导致 HEAD 缺位时先由本地已确认块补位；不够时才拉一次 snapshot；
- 日常新增不允许“为了同步状态”每次全量拉 20 条。

### 7.5 SSE 只做唤醒

~~~http
GET /api/clipboard/stream?cursor=<decimal>&format=wire-v4
Accept: text/event-stream
~~~

- 收到 clipboard 事件后立刻 cursor GET；
- keepalive 后重连；
- 断线指数退避 1、2、5、10、30、60 秒；
- SSE 丢失不影响正确性，cursor GET 才是权威。

### 7.6 即时粘贴与防回环

远端块只有同时满足以下条件才写入系统 clipboard：

1. 用户开了即时粘贴；
2. originDeviceId 不是本机；
3. 检查期间没有用户更晚的新复制；
4. 不是敏感内容，也不是受限共享来源；
5. entryId、内容指纹、changeCount 三项均能建立自写标记。

写入时添加私有 UTI：

~~~text
wang.shurufa.GYInput.clipboard-entry
~~~

内容只含 entryId。捕获层只有“marker/内容指纹/changeCount 同时命中”才跳过；禁止通过“跳过下一个 changeCount”防回环，否则会吞掉用户抢在竞争窗口里的复制。

---

## 8. Capture：四块信息的 macOS 规则

### 8.1 changeCount

macOS 没有公开 clipboard 变更通知，使用 0.2 秒轮询：

- 成功读内容或确认该类型不支持后，才更新 lastChangeCount；
- 声明有文本但 stringForType 为空：最多重试八轮，避免浏览器/Office/Electron 延迟供给丢失；
- 重试时有新 changeCount：放弃旧值，处理最新复制；
- 图片和文件走独立分支，不能被文本重试拖住；
- 两次复制在 0.2 秒内被后者覆盖，系统没有历史队列恢复前者，这是平台物理限制，需如实记录。

### 8.2 文字

- UTF-8、换行、制表符、emoji 均保留；wire 一律 Base64；
- 单条 1 MiB；
- 从 Keep 或卡片再次复制时读取 entry marker，不新建 Keep 条目。

### 8.3 图片

- 输入：PNG 优先，TIFF 次之；
- 卡片先显示缩略图和“同步中”；系统原图不会因远端同步被文本覆盖；
- 远端下载失败显示“图片待下载”，不改变顺序，不拿 [图片] 替代数据；
- Keep Web 展示图片；输入法至少有缩略图、尺寸、状态，点击能重新写 PNG clipboard。

### 8.4 文件与文档

- 记录文件 URL、显示名、类型、大小、preview；
- 立即读取可访问字节或建立 security-scoped bookmark，不能只留短命临时 URL；
- 后端对象上传未定义时状态明确写“仅本机，文件同步待支持”；
- 后续协议必须有哈希、分块、断点续传、大小限制、DELETE 与权限检查。

---

## 9. GY Pulse（核心完成后才做）

Pulse 是同步状态器，不是同步真相。

- 当前焦点屏右下角，内缩 18 pt；
- 宽 42 pt、静态 1 pt 细线；
- 亮点向右：本机上传；向左：刚收到远端事件；
- 多台设备颜色必须服务端 Device 表分配，不能本机乱猜；
- canBecomeKeyWindow = NO；
- ignoresMouseEvents = YES；
- canJoinAllSpaces | stationary | fullScreenAuxiliary；
- 空闲 orderOut、停 timer、释放动画 layer；
- 最短显示 600 ms；设置中可关闭；
- 只能表达“刚收到某设备的内容”，不能伪造“对方此刻在线”。

---

## 10. 实施里程碑

### M1：候选与输入正确性

- [ ] 5 候选 / 5×5 / 25 格固定交互；
- [ ] 精确编码不足时真实候选回退补位；
- [ ] rime 与 directFallback 提交正确，学习不串词；
- [ ] Safari、Chrome、WeChat、VS Code、Terminal 真机失焦测试。

### M2：账户与设置

- [ ] Keychain 会话、登录、退出、错误状态；
- [ ] 五页固定设置；
- [ ] 登录变化重置同步账号状态；
- [ ] 即时粘贴和同步开关即时生效。

### M3：可靠文字同步

- [ ] SQLite、Outbox、旧 TSV 迁移；
- [ ] POST ACK；
- [ ] Snapshot、cursor、DELETE、SSE；
- [ ] 断网 30 条、重启、幂等、不重复验收。

### M4：PNG 图片

- [ ] PNG/TIFF 捕获和本地 blob；
- [ ] SHA-256、10 MiB、PUT ACK；
- [ ] I 事件下载、缩略图、点击复制；
- [ ] Mac ↔ Windows ↔ Keep Web 真机验收。

### M5：体验

- [ ] entryId diff，消除闪烁；
- [ ] 状态颜色和错误文案；
- [ ] 可选 Pulse 视觉原型；
- [ ] 日志仅状态码、耗时、字节数、entryId 前缀。

### M6：共享与文件

共享账户不是“我的多设备”的延伸。共享来源默认只接收、只进 GY 信息流、不覆盖 clipboard；必须有来源、过期、一键暂停和显式授权。未完成该设计，不上线共享写入。

---

## 11. 验收

### 自动化

- [ ] wire-v4 T/I/D、UTF-8、Base64、BigInt cursor；
- [ ] 5×5 fallback、去重、提交映射；
- [ ] 延迟供给、自写竞争、图片/文字分支；
- [ ] 崩溃重启后 Outbox 不丢，20 条不会丢第 21 条；
- [ ] 401、429、503、断网、超时、重复 ACK、SSE 断线；
- [ ] PNG hash 不符、超过 10 MiB、下载 hash 不符。

### 真机

| 场景 | 结果 |
|---|---|
| Mac 复制文字 | 最坏约 0.2 秒出现同步中；⌘V 立即可用 |
| 离线复制 30 条 | 30 条都在 Outbox；联网后均上传；视图仅最新 20 |
| Mac 截图复制 | 原图仍在 clipboard；Keep Web 出现图片 |
| Windows 复制文字/图片 | Mac cursor/SSE 收到；满足开关才即时粘贴 |
| 点 Mac 卡片复制 | clipboard 更新，Keep 不新增重复 |
| Keep 删除 GY 块 | Mac 收到 DELETE 并补位 |
| 同步回写时用户 ⌘C | 用户复制不被吞掉 |
| 应用切换 | 候选窗不遗留、不抢焦点 |

### 性能

- 系统复制到系统粘贴：1–10 ms；
- 系统复制到 GY 卡片：最坏约 200 ms；
- 在线到 Keep ACK：同区域通常几十至数百 ms，不承诺微秒；
- 多设备远端可见：目标 P95 <2 秒；
- 候选输入路径 P95 <16 ms，网络/图片/数据库不计入这条路径。

---

## 12. 构建、签名、发布

本地：

~~~bash
cd "gy输入法/macos"
xcodegen generate
bash scripts/build-macos.sh
bash scripts/smoke-test-core.sh
bash scripts/smoke-test-macos.sh
~~~

Keep API 已真实上线并以测试账号登录后，才运行会写入探针、会操作系统 clipboard 的：

~~~bash
bash scripts/verify-keep-sync.sh
~~~

公共发布必须经过 Apple Silicon 真机构建、Developer ID Application 签名、Developer ID Installer 签名、公证、staple、pkgutil/spctl 校验、不可变 PKG 上传，再推进下载入口。

若 Mac 显示版本使用 2.1.0、Windows 使用 0.10.x，发布 manifest 必须按平台储存版本。现有跨平台同版本校验不能靠伪造版本绕过，先改发布协议再发布。

系统身份 Bundle ID、Input Method connection name、TISInputSourceID 严禁随版本修改。回滚只能安装上一版已签名公证 PKG，随后跑健康检查；不得删除整个 /Library/Input Methods 目录。

---

## 13. 交给 Mac Cloud Code 的执行提示词

~~~text
你在实现 GY 输入法 macOS 2.1「Keep First」。开始前完整阅读：

1. gy输入法/macos/MACOS-KEEP-IMPLEMENTATION-SPEC.md
2. gy输入法/macos/MAC-HANDOFF-20260805.md
3. gy输入法/macos/MACOS-WINDOWS-VI-INTERACTION-AUDIT.md
4. gy输入法/WINDOWS-DESIGN.md
5. gy输入法/GY_LINK_CLIPBOARD_SPEC.md

范围仅限 gy输入法/macos。不要修改 Windows TSF、Rime 词典、GSYEN 登录后端；不要部署、签名、公证或上传生产。

硬约束：
- Keep 是权威；本地 20 条只是 HEAD 视图，Outbox 不受 20 条限制。
- 复制自动进入 Keep；点击卡片复制不能制造重复 Keep 条目。
- 第一版真实完成文字和 PNG；文件/文档没有对象 API 时明确显示待支持。
- 输入/Rime/候选路径零网络。
- macOS clipboard 保持 0.2 秒轮询；lastChangeCount 仅在成功或明确不支持后提交；自写必须 entryId、内容指纹、changeCount 联合匹配。
- 候选界面固定 5×5；编码不足时用真实回退候选补齐，禁止重复、空白或假候选。
- Keychain 保存 refresh token；密码不保存；token、正文、图片不进日志。

实施顺序：M1 候选正确性 → M2 账户 → M3 SQLite Outbox/ACK/cursor → M4 PNG。每阶段都列出改动文件、运行测试，并明确真机或服务端未部署而无法验证的项。保留用户已有改动，禁止 reset、checkout 或删除。

只有 Keep 服务端完成合并、迁移和部署，并且真实探测成功后，才接：
POST /api/clipboard/sync
PUT /api/clipboard/images/{id}?format=ack-v3
GET /api/clipboard/sync?snapshot=1&format=wire-v4
GET /api/clipboard/sync?cursor=...&format=wire-v4
GET /api/clipboard/stream?cursor=...&format=wire-v4
~~~

---

## 14. 完成定义

macOS 2.1 的完成不是“设置页有一个同步开关”，而是：

> Mac 复制文字或截图 → 本机立即可粘贴并显示同步中 → Keep ACK 分配 sequence → Keep Web 出现正确文字/图片 → 其他设备按 cursor 顺序收到 → 点击任一卡片可以再次复制且 Keep 不重复 → 离线、重启、删除、退出登录均不丢失、不乱序、不吞用户复制。

只有这条闭环和第 11 节真机测试通过，macOS 2.1 才可标为可发布。
