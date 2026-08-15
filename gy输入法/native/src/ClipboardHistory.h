#pragma once

// Keep 是跨设备的权威记录库；本机仅投影并缓存最新 20 条文本或 PNG 图片。
// 每条记录有稳定 ID 与 pending 标记，断网后能安全补传而不会把 Keep
// 中已删除的旧记录重新创建出来。

#include <string>
#include <vector>

namespace gy::clipboard_history {

enum class EntryKind { Text, PngImage };

struct Entry {
  std::wstring id;
  unsigned long long unix_time = 0;
  std::wstring text;
  bool pending_upload = false;
  EntryKind kind = EntryKind::Text;
  // Images live as separate PNG files under %LOCALAPPDATA%, never in TSV.
  std::wstring image_sha256;
  // Assigned only after Keep accepts this record. This immutable sequence,
  // not the local device clock, is the order shared by every device.
  unsigned long long sync_sequence = 0;
};

// A Keep cursor page is an ordered event stream, not just a list of rows.
// Preserving ADD/DELETE order matters when an item is restored after deletion.
enum class RemoteChangeKind { Add, Delete };

struct RemoteChange {
  RemoteChangeKind kind = RemoteChangeKind::Add;
  Entry entry;
};

constexpr size_t kMaxEntries = 20;
constexpr size_t kMaxItemBytes = 1048576;  // text: 1 MiB（按 UTF-8 字节计）
constexpr size_t kMaxImageBytes = 10 * 1024 * 1024;

// %LOCALAPPDATA%\GYInput\clipboard-history.tsv（UTF-8、原子替换）。
std::wstring HistoryPath();

// A durable upload outbox separate from the 20-entry local projection. It
// keeps every locally captured item until Keep acknowledges it, so copying the
// 21st item while offline cannot discard the first item's pending upload.
std::wstring OutboxPath();

// 新条目在前（index 0 = 最新）。文件缺失或损坏时返回空。
std::vector<Entry> ReadAll();

// Pending records are oldest first so an offline burst keeps its original
// causal order when the device reconnects.
std::vector<Entry> ReadPendingOutbox();
bool MigratePendingHistoryToOutbox();
bool AcknowledgeUploaded(const std::wstring& id, unsigned long long sync_sequence);

// Keeps pre-onboarding captures on this computer without sending them to Keep.
// The durable outbox is archived locally for audit, while the visible history
// stays available and is marked as local-only (sync_sequence == 0).
bool SkipPendingUploads(size_t* skipped_count);
size_t PendingUploadCount();

// Merge ordered confirmed Keep deltas into the local 20-entry projection.
// Pending local copies stay visible immediately until their ACK arrives.
bool ApplyConfirmedChanges(const std::vector<RemoteChange>& changes);

// A snapshot is authoritative for confirmed entries.  Pending local entries
// not yet visible remotely remain in the projection, while stale confirmed
// rows disappear.  This is used only on startup and after a DELETE to fill
// the 20-entry window without a full reload on every copy.
bool ReplaceConfirmedSnapshot(const std::vector<Entry>& entries);

// 从系统剪贴板读取文本或截图 PNG 并追加一条待同步记录。
// 跳过：空文本、超过上限、与最新一条重复、
// 以及密码管理器等标记了“不要进历史”的敏感内容。
// 返回 true 表示历史发生了变化。
bool AppendFromClipboard();

// 用 Keep 返回的最新 20 条替换本机投影。调用方必须保留仍待上传的条目，
// 以免网络中断时丢失刚复制的文本。
bool ReplaceAll(const std::vector<Entry>& entries);

// 将 Keep 的最新内容写入 Windows 系统剪贴板。后续的 WM_CLIPBOARDUPDATE
// 会被短暂抑制，避免远端同步又被误认为一次新的本地复制。
bool SetSystemClipboardTextFromKeep(const std::wstring& text);

// Reads/writes the durable per-entry PNG asset.  The network worker owns the
// transfer while this module owns Windows clipboard conversion and storage.
bool ReadImagePng(const Entry& entry, std::string* png);
bool SaveImagePngFromKeep(const Entry& entry, const std::string& png);
bool SetSystemClipboardImageFromKeep(const Entry& entry);

// 删除整个历史文件。
bool Clear();

// 当前条目数（ReadAll 的便捷封装）。
size_t Count();

}  // namespace gy::clipboard_history
