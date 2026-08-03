# GY account and sync contract

The planned account domain is `account.shurufa.wang`. HalfSphere Supabase Auth is the intended identity provider, but no production endpoint, key, or redirect URI is stored in this repository until the owner supplies and verifies them.

## Identity boundary

- Windows and macOS use the same Supabase user identity and device list.
- Windows stores refresh credentials only with DPAPI or Windows Credential Manager.
- macOS stores refresh credentials only in Keychain.
- Clients never store passwords, Supabase Service Role Keys, R2 credentials, or plaintext administrator API keys.

## Planned data model

| Record | Scope | Required fields |
| --- | --- | --- |
| `profiles` | one per user | `user_id`, display name, created time |
| `devices` | one per approved device | `device_id`, `user_id`, platform, public label, last seen, revoked time |
| `input_preferences` | one current profile | mode, simplified/traditional choice, candidate options, updated time |
| `phrase_entries` | user-owned | phrase, expansion, locale, updated time, deleted time |
| `lexicon_events` | user-owned learning events | opaque word id, selection count, updated time; never raw keystroke history |
| `clipboard_items` | opt-in and end-to-end encrypted | device id, ciphertext, expiry, content type; no server-side plaintext |

All tables require row-level security keyed by `auth.uid()`. Device registration must be revocable. Clipboard synchronization remains off until its encryption, expiry, and deletion behavior are independently reviewed.

## Rollout

1. Create and verify `account.shurufa.wang` and Supabase redirect URLs.
2. Ship sign-in and device listing without input or clipboard synchronization.
3. Add settings and phrase sync behind an explicit opt-in.
4. Add encrypted clipboard sync only after cross-device threat modeling and key-management review.
