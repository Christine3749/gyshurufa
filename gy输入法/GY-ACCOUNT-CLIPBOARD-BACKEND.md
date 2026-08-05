# GY 账户绑定与剪贴板后端集成设计（GY × HalfSphere）

> 版本：2026-08-05 · 状态：待实施
> 上位文件：`GY_LINK_CLIPBOARD_SPEC.md`、`CLIPBOARD-PAGE-DESIGN.md`、产品标准 §6
> 后端落点：`HS/halfsphere-api`（Hono + Postgres，Cloud Run）· 存储：GCP Cloud Storage · 认证：Supabase Auth

## 1. 现状盘点（已核实）

| 组件 | 事实 |
|---|---|
| `halfsphere`（Next.js） | Supabase Auth 登录体系（cookie + Bearer JWT），域名 halfsphere.com |
| `halfsphere-api`（Hono） | Cloud Run 部署（env.yaml），已配置 `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY`（可验 JWT）、`DATABASE_URL`（Supabase Postgres 或 Cloud SQL） |
| GCP | Cloud Run 在用 ⇒ GCP 项目已存在；GCS 尚未使用 |
| GY 端 | 设置面板"账户"页只有本地标识；会员层（Agent）未建；红线：客户端不存 Service Role Key、不存明文密码/令牌，Windows 用 DPAPI、macOS 用 Keychain |

**结论：不需要新建后端。** 在 `halfsphere-api` 增加 `/gy/*` 路由组即可；GY 复用 Supabase 账户体系，剪贴板密文进 GCS。

## 2. 账号绑定流程（设备码授权，输入法不开内嵌浏览器）

```text
GY 设置-账户页 点"绑定账号"
  │  POST /gy/devices/code                      （无需登录）
  │  ← { device_code, user_code: "GY-4K7X", verify_url, expires_in: 600 }
  ▼
设置页显示：打开 halfsphere.com/gy 输入 GY-4K7X   （用户可在任意设备完成）
  │  用户在该页用 Supabase 账户登录并确认授权这台设备
  ▼
GY 每 3 秒轮询 POST /gy/devices/token { device_code }
  │  未授权 → 426/pending；已授权 →
  │  ← { device_token, device_id, username }   -- 只回用户名，不回邮箱等档案
  ▼
device_token 写入 DPAPI（Windows）/ Keychain（macOS）
设置页账户卡片变为已绑定态：邮箱 + 设备名 + "解除绑定"
```

- `device_token`：长期有效的随机令牌（≥256bit），服务端只存 **哈希**；吊销即删库记录。
- 绑定同时完成**设备注册**：写入 `gy_devices`（device_id, user_id, 设备名, 平台, 公钥——为 E2E 加密预留）。
- 解除绑定：设置页按钮 → `DELETE /gy/devices/<id>` → 服务端吊销 + 本地清除令牌。

## 3. 剪贴板 API（device_token 鉴权，Bearer）

| 端点 | 说明 |
|---|---|
| `POST /gy/clipboard` | 上传一条剪贴板。body：`{ item_id, source_device_id, content_type, size, ciphertext_b64, nonce, ts, ttl_seconds }`。**body 即密文**，服务端不可读 |
| `GET /gy/clipboard?since=<item_id>&limit=20` | 拉取本用户其他设备的新条目（轮询，MVP 30s 间隔 + 本地去重） |
| `DELETE /gy/clipboard/<item_id>` | 单条删除（清空历史时逐条/批量） |
| `POST /gy/clipboard/clear` | 清空本用户全部条目 |

- **大条目进 GCS**：>64 KB 的密文写 GCS bucket（建议 `gy-clipboard-prod`），路径 `users/<uid>/items/<item_id>.bin`，Postgres 只存元数据 + `gcs_path`；≤64 KB 直接存 Postgres `bytea`，省一次往返。
- **GCS 生命周期规则**：1 天自动删除（对应规格的 24h TTL），Postgres 行同步过期（`expires_at` + 定时清理或 `pg_cron`）。
- 单条上限 1 MiB（CLIPBOARD-PAGE-DESIGN 已定），超限 413。
- 速率限制：每设备 60 次/分钟，防失控循环打爆后端。

## 4. 数据模型（Supabase Postgres 新增）

```sql
create table gy_devices (
  device_id    uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  platform     text not null,            -- windows | macos（只存平台泛称，不存设备名）
  public_key   bytea,                    -- E2E 预留
  token_hash   text not null,
  created_at   timestamptz default now(),
  revoked_at   timestamptz
);

create table gy_device_codes (
  device_code  text primary key,
  user_code    text unique not null,     -- GY-4K7X
  device_name  text, platform text,
  approved_by  uuid references auth.users(id),
  expires_at   timestamptz not null
);

create table gy_clipboard_items (
  item_id      text primary key,         -- 客户端生成 ULID
  user_id      uuid not null references auth.users(id) on delete cascade,
  source_device uuid references gy_devices(device_id),
  content_type text not null,            -- text/plain 一期
  size         int  not null,
  gcs_path     text,                     -- null = 内联 ciphertext
  ciphertext   bytea,
  nonce        bytea not null,
  created_at   timestamptz default now(),
  expires_at   timestamptz not null
);
create index on gy_clipboard_items (user_id, created_at);
-- RLS: 一律 denied，只走 service role（后端持有），客户端永不直连 Supabase
```

## 5. 安全边界（不可妥协）

0. **数据最小化（产品决策 2026-08-05）：HalfSphere 只放用户名，其他信息一概不放。** GY 自有表不镜像邮箱、手机号、头像等任何档案信息；授权响应只回 `username`；日志不落用户标识；设备名不进库（设备列表只显示平台泛称"Windows 设备"/"Mac 设备"+ 绑定时间）。
1. GY 客户端**只持 device_token**；Supabase anon key 不出现在输入法任何进程；Service Role Key 只在 halfsphere-api。
2. 剪贴板内容**端到端加密**：MVP 可先用"账户级数据密钥"（绑定后从服务端领取、密文存储、device_token 换取），二期升级设备组密钥 + 验签（规格完整模型）。
3. 令牌存储：Windows DPAPI / macOS Keychain，与产品标准 §6 一致。
4. 同步内容不进日志：halfsphere-api 对 `/gy/clipboard` 路由禁用 body 日志。
5. 敏感内容拦截在**客户端**做（验证码/密码管理器来源不入上传队列）——服务端无法识别密文，也不该能识别。

## 6. 与三层架构的关系

```text
GYLinkAgent（会员层，新进程）
   │  HTTPS + device_token            ← 唯一出网通道
   ▼
halfsphere-api /gy/*（Cloud Run）
   ├─ Supabase Auth：设备码授权确认页（halfsphere.com/gy，Next.js 加一页）
   ├─ Postgres：devices / items 元数据
   └─ GCS：大条目密文（1 天生命周期）
TSF DLL / 输入引擎：零网络，永不变。
```

## 7. 实施分阶段

| 阶段 | 内容 | 出口标准 |
|---|---|---|
| **B1 绑定** | `gy_devices`/`gy_device_codes` 表 + 3 个端点 + halfsphere.com/gy 授权页 + GY 设置页"绑定账号"按钮与已绑定态 | 两端真机完成绑定/解绑 |
| **B2 剪贴板 MVP** | `gy_clipboard_items` + 上传/拉取端点 + Windows Agent 监听 `WM_CLIPBOARDUPDATE` + 防环标记 + FIFO 20 条 | A 机复制 → B 机 ⌘V/Ctrl+V 直接出 |
| **B3 Mac 接入 + GCS** | Mac Agent（NSPasteboard changeCount）+ GCS 大条目 + 生命周期 | 三端互通 |
| **B4 加固** | E2E 设备组密钥、敏感内容规则、暂停同步、设备管理 UI | 过 GY_LINK_CLIPBOARD_SPEC 验收标准 |
