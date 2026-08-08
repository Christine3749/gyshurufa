# macOS 会话交接 · 2026-08-08

上一轮会话的完整状态。读这份是为了**不重复我踩过的坑**——其中一个让我把整套功能实现在了错误的目录里，白做一轮。

配套阅读：`MACOS-KEEP-IMPLEMENTATION-SPEC.md`（目标架构），本文是**当前现实**。

---

## 一、最重要的：源码树在哪

这台 Mac 上有 **四份** macOS 源码，只有一份是真的。

| 路径 | 版本 | 状态 |
|---|---|---|
| `github-gyshurufa/gyinput-macos-stage4/gy输入法/macos` | **2.1.2 / build 212** | ✅ **唯一有效**，构建出来的就是已安装的 |
| `shurufa/gy输入法/macos` | 1.0.8 / build 13 | ❌ 陈旧，落后约 200 个 build |
| `github-gyshurufa/gy输入法/macos` | build 13 | ❌ 陈旧 |
| `…stage4.snapshot-20260807/` | — | 我做的快照，可删 |

**我第一轮把全部功能实现在了第二行那棵树上**，因为规格书描述的文件（`project.yml`、`build-macos.sh`、`GYClipboardHistory.m`）在那里不存在，我误判成"规格书写错了"。实际是规格书完全正确，只是描述的是 stage4。

判断方法：`GYCandidateGovernance`、`GYRimeRuntime` 只存在于 stage4。

网站同理有四份，**部署的是 `~/Desktop/shurufa/gy输入法---官方网站`**（唯一带 `.vercel/`，用 `vercel deploy --prod` 从本地发，没连 Git）。

---

## 二、代码现状

### 仓库与分支（均已推送）

```
gyshurufa（现已 PUBLIC）
  main                        6d0fd57   含 MACOS-KEEP-IMPLEMENTATION-SPEC.md
  codex/macos-stage4          c8cdff6   ← macOS 主线，我的 13 个提交已合入
  keep-clipboard-sync         3027c41   我的分支（已合并，可留可删）
  codex/gy-0.10.62-sync-cursor 2568fec  Codex 的 Windows 侧

GyenBox（PUBLIC）
  main                        d063d80   只有 take:20 全量模型 + 图片
  codex/keep-image-sync-01061 c2fcce1   图片同步（已部署）
  codex/keep-sync-cursor-01062 2bf366b  ⚠️ v3 协议，未合 main、未部署
```

### 已实现（macOS 2.1.2）

- `GYAccountAuth` — GSYEN 登录；refresh token 存 Keychain（`wang.shurufa.GYInput.gsyen` / `session`，device-only + after-first-unlock）；access token 只在内存；密码不落盘
- `GYKeepSync` — 3 秒串行队列轮询；pending 按最旧优先上传；拉取以 Keep 返回为准
- `GYClipboardHistory` — 20 条窗口；四字段格式 `<id>\t<unix_ts>\t<pending>\t<escaped>`；旧两字段行无损迁移（实测 20/20 字节一致）
- 设置面板剪贴板页、真实登录卡、同步状态行
- 系统输入菜单改为微信式动作命名（`切换至繁体输入`），加「剪贴板」入口

### 已修复的坑（多数早于本次功能）

| 问题 | 根因 |
|---|---|
| 设置面板输入框点不进去 | 无边框窗口 `canBecomeKeyWindow` 默认 NO，**面板里任何输入框都拿不到焦点** |
| 复制静默丢失 | `changeCount` 记账早于读取；数据后填**不会**再次推进 changeCount，所以没有第二次机会 |
| 同步写回吞掉用户复制 | 写入远端内容后直接记账；改为按**内容指纹 + changeCount 双条件**匹配 |
| 简繁切换无效 | IMK 把菜单 action 发给 **IMKInputController**，不理会菜单项 target；且 `tag` 跨进程不保留。**已实测确认**（日志 `GY menu: EN (controller)`） |
| 同步连续打转 | 每轮同步发通知唤醒下一轮 |
| 设置切页卡 | 每张卡片用 `boundingRectWithSize:` 以 `CGFLOAT_MAX` 高度测量**完整**文本，只为得出 `MIN(4,…)` |

---

## 三、已知未修（按优先级）

1. **离线连拍超 20 条会真丢数据。** outbox 寄生在 20 条窗口里，第 21 条把最早那条挤出后就永远传不到 Keep。这是唯一的数据丢失路径。
2. **上传成功后 pending 位不落盘。** `GYKeepSync` 直接改 `_items` 里的对象，`replaceEntries:` 比对时两边已经一样 → 判定"无变化" → 跳过写盘。后果：验证脚本永远报"Keep 未确认"，`⌘C → Keep` 时延**至今一次都没测出来**。几行就能修，但它挡着所有测量。
3. **无图片。** 仍用 `format=wire`。服务端 `wire-v2` 和 `PUT /api/clipboard/images/{id}` 都已上线可用，**这条不依赖 v3 协议，现在就能做**。
4. 整表替换，未按 `entryId` diff。
5. GY Pulse 未开始。

---

## 四、Keep 服务端真实状态

**别信"已完成"的描述，端点会说话：**

```
/api/clipboard                    401  ✅ 存在（take:20 全量模型）
/api/clipboard?format=wire-v2     401  ✅ 图片可用
PUT /api/clipboard/images/{id}    ✅   PNG + x-gy-sha256 + x-gy-captured-at，≤10MB
/api/clipboard/changes            404  ❌ 不存在
/api/clipboard/ack                404  ❌ 不存在
/api/devices                      404  ❌ 不存在
```

对照组 `/api/clipboard/definitely-not-real` 也是 404，所以 404 确实代表不存在。

**Mac 切到 v3 之前，`codex/keep-sync-cursor-01062` 必须先合并 + 迁移数据库 + 部署。** 现在只是推上了分支。

服务端排序目前是 `orderBy: [{capturedAt: desc}]`，而 **`capturedAt` 是客户端传的**——时钟偏差或恶意客户端可以把自己钉在顶端。这是 `globalSequence` 真正要解决的问题。

---

## 五、构建与发布

```bash
cd ~/Desktop/shurufa/github-gyshurufa/gyinput-macos-stage4/gy输入法/macos
export GY_DEVELOPER_IDENTITY="Apple Development: ethan7586@gsyen.com (C522V6WTRJ)"
GY_RELEASE_VERSION=2.1.3 ./scripts/build-macos.sh      # 版本去掉点 = build 213
rm -rf build/GYInput.app && cp -R .build/DerivedData/Build/Products/Release/GYInput.app build/
./scripts/package-core.sh
sudo installer -pkg build/GYInput-core.pkg -target /
```

**build 号必须严格递增。** `installer` 会拿已装版本比对，判定降级后**静默跳过组件，同时报告 "The upgrade was successful"**——今天因此浪费过一轮。真相只在 `/var/log/install.log` 的 `Skipping component`。

卸载用 `scripts/uninstall-gyinput.sh [--purge-data]`，会清五个历史收据 ID。

**签名现状：只有 Apple Development 证书，没有 Developer ID、没有公证凭据。** 所以 `publish-r2.sh` 的闸门（要求 `signed && notarized`）过不去，站点的官方 macOS 下载仍是 `available: false`。当前 macOS 分发走 GitHub Releases。

验证脚本：`scripts/verify-keep-sync.sh`（注意它会因为上面第 2 条而误报"未确认"）。

---

## 六、线上

```
https://www.shurufa.wang        Vercel 项目 gy-shurufa，CLI 部署
  Windows 0.10.61               官方接口，实测可下 10,118,392 字节
  macOS   2.1.2 Preview         指向 GitHub Release，卡片内附 sudo installer 命令
```

⚠️ **部署树里有约 500 行从未进过生产的改动**（`download-worker/src/index.ts` 147 行、`DownloadSection.tsx` 208 行等），2026-08-08 那次发布把它们一并上线了。构建通过，但没有专门验收过，下载区如有异常先查这里。

---

## 七、反复出现的模式

**「已部署」和「已推送」在这个项目里是两件事**，一天之内撞见五次：Windows 0.9.57 领先远端、`apps/keep` 未跟踪、Keep 剪贴板路由未合 main、macOS stage4 未推、Keep v3 只在本地。

**结论：任何"某功能已完成"的说法，先探端点或读代码，别信描述。** 今天有三次我从代码推断根因、事后被证明是错的；唯一一次正确的诊断是靠 `sample` 和日志拿到的实际数据。
