#include "ClipboardHistory.h"
#include "ClipboardHistoryTest.h"

#include <windows.h>

#include <iostream>
#include <string>
#include <vector>

namespace {

using gy::clipboard_history::Entry;
using gy::clipboard_history::EntryKind;
using gy::clipboard_history::RemoteChange;
using gy::clipboard_history::RemoteChangeKind;

Entry Text(const wchar_t* id, const wchar_t* text, unsigned long long sequence) {
  return {id, 1700000000ULL + sequence, text, false, EntryKind::Text, L"", sequence};
}

bool HasOrder(const std::vector<Entry>& entries, std::initializer_list<const wchar_t*> ids) {
  if (entries.size() != ids.size()) return false;
  size_t index = 0;
  for (const wchar_t* id : ids) {
    if (entries[index++].id != id) return false;
  }
  return true;
}

int Fail(const char* message) {
  std::cerr << "ClipboardHistorySyncSmoke: " << message << "\n";
  return 1;
}

}  // namespace

int main() {
  wchar_t temporary[MAX_PATH]{};
  if (!GetTempPathW(MAX_PATH, temporary)) return Fail("could not resolve temporary directory");
  const std::wstring local_app_data = std::wstring(temporary) + L"GYClipboardSyncSmoke-" +
      std::to_wstring(GetCurrentProcessId());
  if (!CreateDirectoryW(local_app_data.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) {
    return Fail("could not create isolated LOCALAPPDATA");
  }
  if (!SetEnvironmentVariableW(L"LOCALAPPDATA", local_app_data.c_str())) return Fail("could not isolate LOCALAPPDATA");
  if (!gy::clipboard_history::Clear()) return Fail("could not clear isolated history");

  // The durable outbox is not capped by HEAD(20).  This fixture represents a
  // locally captured record whose visual slot may later be displaced, but
  // whose upload must survive until the server acknowledgement is durable.
  const std::wstring pending_id = L"sync-smoke-pending";
  const std::string pending_row = "sync-smoke-pending\t1700000040\t1\tT\tpending\t\t0\n";
  {
    HANDLE file = CreateFileW(gy::clipboard_history::HistoryPath().c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return Fail("could not seed pending history");
    DWORD written = 0;
    const bool wrote = WriteFile(file, pending_row.data(), static_cast<DWORD>(pending_row.size()), &written, nullptr) &&
        written == pending_row.size();
    CloseHandle(file);
    if (!wrote) return Fail("could not write pending history fixture");
  }
  if (!gy::clipboard_history::MigratePendingHistoryToOutbox() ||
      gy::clipboard_history::ReadPendingOutbox().size() != 1 ||
      !gy::clipboard_history::AcknowledgeUploaded(pending_id, 9)) {
    return Fail("pending upload was not durably acknowledged");
  }
  const std::vector<Entry> after_ack = gy::clipboard_history::ReadAll();
  if (after_ack.size() != 1 || after_ack.front().id != pending_id || after_ack.front().pending_upload ||
      after_ack.front().sync_sequence != 9 || !gy::clipboard_history::ReadPendingOutbox().empty()) {
    return Fail("ACK did not atomically project confirmation and clear retry state");
  }
  if (!gy::clipboard_history::Clear()) return Fail("could not reset isolated history after ACK test");

  // First-login onboarding must be able to retain local captures without
  // replaying an offline backlog into Keep.  The retry manifest is archived,
  // the visible entry stays local-only, and later migration must not recreate it.
  {
    HANDLE file = CreateFileW(gy::clipboard_history::HistoryPath().c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return Fail("could not seed skip-history fixture");
    DWORD written = 0;
    const bool wrote = WriteFile(file, pending_row.data(), static_cast<DWORD>(pending_row.size()), &written, nullptr) &&
        written == pending_row.size();
    CloseHandle(file);
    if (!wrote || !gy::clipboard_history::MigratePendingHistoryToOutbox()) return Fail("could not seed skip outbox");
  }
  size_t skipped = 0;
  if (!gy::clipboard_history::SkipPendingUploads(&skipped) || skipped != 1 ||
      !gy::clipboard_history::ReadPendingOutbox().empty() ||
      !gy::clipboard_history::MigratePendingHistoryToOutbox() ||
      !gy::clipboard_history::ReadPendingOutbox().empty()) {
    return Fail("skipped onboarding records were queued for upload");
  }
  const std::vector<Entry> after_skip = gy::clipboard_history::ReadAll();
  if (after_skip.size() != 1 || after_skip.front().pending_upload || after_skip.front().sync_sequence != 0) {
    return Fail("skip did not retain a local-only history entry");
  }
  if (!gy::clipboard_history::Clear()) return Fail("could not reset isolated history after skip test");

  // This exercises the production screenshot conversion path without opening
  // the real clipboard: an off-screen bitmap becomes PNG, is stored exactly
  // as a screenshot asset, and remains readable from the confirmed HEAD.
  const DWORD pixels[] = {0xff113355, 0xff66aa22, 0xffcc4422, 0xffeeeeee};
  HBITMAP bitmap = CreateBitmap(2, 2, 1, 32, pixels);
  std::string png;
  if (!bitmap || !gy::clipboard_history::testing::EncodeBitmapAsPng(bitmap, &png)) {
    if (bitmap) DeleteObject(bitmap);
    return Fail("could not convert an in-memory screenshot bitmap to PNG");
  }
  DeleteObject(bitmap);
  if (png.size() < 8 || png.compare(0, 8, "\x89PNG\r\n\x1a\n", 8) != 0) {
    return Fail("screenshot conversion did not produce a PNG asset");
  }
  const Entry image{L"sync-smoke-image", 1700000050ULL, L"[图片]", false, EntryKind::PngImage, L"", 8};
  if (!gy::clipboard_history::SaveImagePngFromKeep(image, png) ||
      !gy::clipboard_history::ReplaceConfirmedSnapshot({image})) {
    return Fail("could not persist screenshot asset in the confirmed HEAD");
  }
  std::string restored_png;
  const std::vector<Entry> image_head = gy::clipboard_history::ReadAll();
  if (image_head.size() != 1 || image_head.front().kind != EntryKind::PngImage ||
      !gy::clipboard_history::ReadImagePng(image_head.front(), &restored_png) || restored_png != png) {
    return Fail("screenshot PNG asset did not survive the local projection round trip");
  }
  if (!gy::clipboard_history::Clear()) return Fail("could not reset isolated history after image test");

  // A remote write must be ignored exactly once, and only for the Windows
  // clipboard sequence it created.  A user who copies immediately afterwards
  // gets a new sequence and must never be swallowed by the two-second guard.
  gy::clipboard_history::testing::SuppressRemoteText(L"remote text", 100);
  if (gy::clipboard_history::testing::IsSuppressedRemoteText(L"remote text", 101)) {
    return Fail("a user text copy after a remote write was incorrectly suppressed");
  }
  gy::clipboard_history::testing::SuppressRemoteText(L"remote text", 102);
  if (!gy::clipboard_history::testing::IsSuppressedRemoteText(L"remote text", 102) ||
      gy::clipboard_history::testing::IsSuppressedRemoteText(L"remote text", 102)) {
    return Fail("a remote text write was not suppressed exactly once");
  }
  gy::clipboard_history::testing::SuppressRemoteImage(200);
  if (gy::clipboard_history::testing::TakeSuppressedRemoteImage(201)) {
    return Fail("a user image copy after a remote write was incorrectly suppressed");
  }
  gy::clipboard_history::testing::SuppressRemoteImage(202);
  if (!gy::clipboard_history::testing::TakeSuppressedRemoteImage(202) ||
      gy::clipboard_history::testing::TakeSuppressedRemoteImage(202)) {
    return Fail("a remote image write was not suppressed exactly once");
  }

  const Entry first = Text(L"sync-smoke-first", L"first", 10);
  const Entry deleted = Text(L"sync-smoke-deleted", L"deleted", 20);
  if (!gy::clipboard_history::ReplaceConfirmedSnapshot({first, deleted}) ||
      !HasOrder(gy::clipboard_history::ReadAll(), {L"sync-smoke-deleted", L"sync-smoke-first"})) {
    return Fail("initial snapshot did not create the expected HEAD");
  }

  const Entry middle = Text(L"sync-smoke-middle", L"middle", 22);
  const Entry restored = Text(L"sync-smoke-deleted", L"restored", 23);
  const Entry deletion_marker{L"sync-smoke-deleted", 0, L"", false, EntryKind::Text, L"", 21};
  const std::vector<RemoteChange> changes{
      {RemoteChangeKind::Delete, deletion_marker},
      {RemoteChangeKind::Add, middle},
      {RemoteChangeKind::Add, restored},
  };
  if (!gy::clipboard_history::ApplyConfirmedChanges(changes) ||
      !HasOrder(gy::clipboard_history::ReadAll(),
                {L"sync-smoke-deleted", L"sync-smoke-middle", L"sync-smoke-first"})) {
    return Fail("ordered ADD/DELETE/ADD stream was not applied correctly");
  }

  const Entry newest = Text(L"sync-smoke-newest", L"newest", 30);
  if (!gy::clipboard_history::ReplaceConfirmedSnapshot({newest, middle, first}) ||
      !HasOrder(gy::clipboard_history::ReadAll(),
                {L"sync-smoke-newest", L"sync-smoke-middle", L"sync-smoke-first"})) {
    return Fail("authoritative snapshot did not remove deleted data or fill the HEAD");
  }

  gy::clipboard_history::Clear();
  RemoveDirectoryW((local_app_data + L"\\GYInput\\clipboard-assets").c_str());
  RemoveDirectoryW((local_app_data + L"\\GYInput").c_str());
  RemoveDirectoryW(local_app_data.c_str());
  std::cout << "ClipboardHistorySyncSmoke: PASS\n";
  return 0;
}
