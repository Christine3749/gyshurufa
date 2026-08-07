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
