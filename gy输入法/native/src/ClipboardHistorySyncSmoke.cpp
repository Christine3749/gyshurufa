#include "ClipboardHistory.h"

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
