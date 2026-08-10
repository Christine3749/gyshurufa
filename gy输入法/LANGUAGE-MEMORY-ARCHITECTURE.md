# GY 语言记忆架构 v1

## 目标

把输入法、公共词库和 Keep 学习记忆连接起来，同时保证基础输入完全离线。
三个服务共用 GY 账户与同步底座，但不共享未经授权的原始输入数据。

```text
shurufa.gyenbox.com  个人输入体验与候选学习
        │
        ├── 本地词库快照 + 本地词频
        ├── 个人学习投影（用户授权后同步）
        │
ciku.gyenbox.com     公共词库、词条、版本和聚合词频
        │
keep.gyenbox.com     用户主动保存的词源、例句和复习卡片
```

## 服务边界

### shurufa

- 输入法设置、隐私开关和同步状态；
- 本地 `once / memory / high / fixed` 候选等级；
- 下载签名词库快照；
- 只在用户授权后提交个人学习投影；
- 输入时不调用网络、Keep 或 AI。

### ciku

- 发布带版本号和 SHA-256 的基础词库；
- 管理拼音、词条、来源和审核状态；
- 保存匿名聚合词频，不保存个人原始输入；
- 提供离线快照和增量更新；
- 词库更新不能覆盖用户固定词和个人词频。

### keep

- 保存用户主动确认的长期学习卡片；
- 保存词源、词根拆解、例句、关联词和复习时间；
- 与剪贴板事件流分离；
- 允许用户查看、修改、导出和删除。

## 数据类型

### 个人学习投影

个人学习只同步统计投影，不同步原始按键事件：

```json
{
  "schema": "gy.ime_learning.v1",
  "pinyin": "lihouyi",
  "candidate": "李厚毅",
  "count": 4,
  "recent7Days": 2,
  "recent30Days": 4,
  "activeDays": 3,
  "pinned": false,
  "updatedAt": "2026-08-10T00:00:00Z"
}
```

### Keep 学习卡片

```json
{
  "schema": "gy.memory_card.v1",
  "kind": "word_origin",
  "surface": "transport",
  "pinyin": "",
  "meaning": "运输；交通",
  "origin": "trans = 穿过，port = 搬运",
  "relatedWords": ["import", "export", "portable"],
  "examples": ["Public transport is convenient."],
  "source": "ai",
  "confidence": 0.86,
  "approved": true,
  "privacy": "account",
  "createdAt": "2026-08-10T00:00:00Z"
}
```

## 推荐接口边界

接口名称是逻辑契约，实际部署可以使用同一 API 网关：

```text
GET  /v1/dictionary/snapshot
GET  /v1/dictionary/changes?from=<version>
GET  /v1/ime-learning
PUT  /v1/ime-learning/<pinyin>/<candidate>
GET  /v1/memory/cards
POST /v1/memory/cards
PATCH /v1/memory/cards/<id>
DELETE /v1/memory/cards/<id>
```

所有接口都必须按 GY 账户隔离。`dictionary` 可以公开只读快照；`ime-learning`
和 `memory` 必须经过账户授权，服务端不能通过 URL 或日志泄露词条内容。

## 同步原则

1. 本地输入永远先完成，后台同步失败不得阻塞候选窗；
2. 使用版本号、幂等键和合并规则，重复上传不能重复累计；
3. 固定词以用户明确操作为准，不能被公共词库覆盖；
4. 删除和清空必须同步 tombstone，避免旧设备重新恢复；
5. 词库快照必须签名并校验 SHA-256；
6. AI 只处理用户明确点击的词，不处理后台输入流；
7. AI 词源结果必须显示来源、置信度，并允许用户修正后再保存。

## 实施顺序

1. Windows 本地分层（已完成）；
2. Keep 增加独立 `memory_cards` 数据类型；
3. shurufa 增加个人学习投影同步；
4. ciku 发布签名词库快照和聚合词频；
5. 候选框增加“词源 / 记住 / 保存到 Keep”入口；
6. AI 生成词源卡片和间隔复习计划。
