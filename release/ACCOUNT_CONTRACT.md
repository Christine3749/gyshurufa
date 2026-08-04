# GY account and sync contract

The planned account domain is `account.shurufa.wang`. HalfSphere Supabase Auth is the intended identity provider, but no production endpoint, key, or redirect URI is stored in this repository until the owner supplies and verifies them.

完整架构边界见 [三层架构契约](ARCHITECTURE_CONTRACT.md)。本文件只定义账户和同步数据；账户能力由独立 Agent 实现，不能进入输入 Core 或 Engine 的按键路径。

## Identity boundary

- Windows and macOS use the same Supabase user identity and device list.
- Windows stores refresh credentials only with DPAPI or Windows Credential Manager.
- macOS stores refresh credentials only in Keychain.
- Clients never store passwords, Supabase Service Role Keys, R2 credentials, or plaintext administrator API keys.
- `user_id` 是唯一不可变身份；可选 `handle`（用户名）与 `display_name` 都可修改，不能作为数据主键或加密材料。

## Planned data model

| Record | Scope | Required fields |
| --- | --- | --- |
| `profiles` | one per user | `user_id`, normalized unique handle, display name, created time |
| `devices` | one per approved device | `device_id`, `user_id`, platform, public label, last seen, revoked time |
| `input_preferences` | one current profile | mode, simplified/traditional choice, candidate options, updated time |
| `phrase_entries` | user-owned | phrase, expansion, locale, updated time, deleted time |
| `lexicon_events` | user-owned learning events | opaque word id, selection count, updated time; never raw keystroke history |
| `clipboard_items` | opt-in and end-to-end encrypted | device id, ciphertext, expiry, content type; no server-side plaintext |

All tables require row-level security keyed by `auth.uid()`. Device registration must be revocable. Clipboard synchronization remains off until its encryption, expiry, and deletion behavior are independently reviewed.

## Local account lifecycle

1. First launch creates an offline local profile; typing never requires sign-in.
2. Settings opens the Agent-owned sign-in flow; the first method is email Magic Link, with Passkey evaluated later.
3. Sign-in may show devices and profile details, but does not upload phrases, learning, or clipboard data until each category is enabled.
4. Sign-out preserves local typing; the user explicitly chooses whether to keep or clear the local synchronized copy.
5. Revoking a device blocks future sync; encrypted clipboard groups rotate their key.

## Rollout

1. Create and verify `account.shurufa.wang` and Supabase redirect URLs.
2. Ship Agent-owned sign-in and device listing without input or clipboard synchronization.
3. Add settings and phrase sync behind an explicit opt-in.
4. Add encrypted clipboard sync only after cross-device threat modeling and key-management review.
