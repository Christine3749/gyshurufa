#pragma once

#include <windows.h>

#include <cstdint>
#include <iterator>
#include <string>
#include <string_view>

namespace gy::input_scope_cache {

// This mapping is a one-way, metadata-only bridge from the out-of-process
// Host probe to TSF DLLs.  It never contains field text, selection, clipboard
// data, typed keys, or a network-derived value.
constexpr wchar_t kCacheName[] = L"Local\\GYInput.InputScopeCache.v1";
constexpr DWORD kSnapshotTtlMs = 1500;

struct Snapshot {
  volatile LONG sequence = 0;  // seqlock: odd while Host writes
  DWORD foreground_process_id = 0;
  HWND foreground_window = nullptr;
  ULONGLONG captured_tick = 0;
  LONG direct = 0;
  LONG sensitive = 0;
};

enum class ReadStatus {
  Unavailable,
  Busy,
  NoForeground,
  ForegroundWindowMismatch,
  ProcessUnavailable,
  ProcessMismatch,
  Expired,
  Match
};

struct ReadDiagnostics {
  ReadStatus status = ReadStatus::Unavailable;
  HWND snapshot_window = nullptr;
  HWND foreground_window = nullptr;
  DWORD snapshot_process_id = 0;
  DWORD foreground_process_id = 0;
  ULONGLONG age_ms = 0;
  bool direct = false;
  bool sensitive = false;
};

inline const std::wstring& CacheName() {
#ifdef GY_TESTING
  static const std::wstring name = [] {
    wchar_t value[256]{};
    constexpr wchar_t kPrefix[] = L"Local\\GYInput.InputScopeCache.test.";
    const DWORD length = GetEnvironmentVariableW(L"GYINPUT_SCOPE_CACHE", value,
                                                  static_cast<DWORD>(std::size(value)));
    if (length && length < std::size(value) && std::wstring_view(value).rfind(kPrefix, 0) == 0) {
      return std::wstring(value);
    }
    return std::wstring{};
  }();
  return name;
#else
  static const std::wstring name(kCacheName);
  return name;
#endif
}

class Reader {
 public:
  Reader() = default;
  ~Reader() {
    if (view_) UnmapViewOfFile(view_);
    if (mapping_) CloseHandle(mapping_);
  }
  Reader(const Reader&) = delete;
  Reader& operator=(const Reader&) = delete;

  // Called only on focus/activation paths, never from a key callback.
  void Attach() {
    if (view_ || CacheName().empty()) return;
    mapping_ = OpenFileMappingW(FILE_MAP_READ, FALSE, CacheName().c_str());
    if (mapping_) view_ = static_cast<const Snapshot*>(MapViewOfFile(mapping_, FILE_MAP_READ, 0, 0, sizeof(Snapshot)));
    if (!view_ && mapping_) { CloseHandle(mapping_); mapping_ = nullptr; }
  }

  bool ReadForCurrentForeground(bool* direct, bool* sensitive,
                                ReadDiagnostics* diagnostics = nullptr) const {
    ReadDiagnostics result{};
    if (!view_ || !direct || !sensitive) {
      if (diagnostics) *diagnostics = result;
      return false;
    }
    Snapshot value{};
    bool snapshot_read = false;
    for (unsigned attempt = 0; attempt < 2; ++attempt) {
      // Reader mappings are intentionally FILE_MAP_READ.  A locked
      // InterlockedCompareExchange would write even when exchanging the same
      // value and fault in a target process.  Volatile loads plus the Host
      // writer's seqlock and memory barriers give us a read-only snapshot.
      const LONG before = view_->sequence;
      if (before & 1) continue;
      MemoryBarrier();
      value.foreground_process_id = view_->foreground_process_id;
      value.foreground_window = view_->foreground_window;
      value.captured_tick = view_->captured_tick;
      value.direct = view_->direct;
      value.sensitive = view_->sensitive;
      MemoryBarrier();
      const LONG after = view_->sequence;
      if (before == after && !(after & 1)) {
        snapshot_read = true;
        break;
      }
    }
    if (!snapshot_read) {
      result.status = ReadStatus::Busy;
      if (diagnostics) *diagnostics = result;
      return false;
    }
    const HWND foreground = GetForegroundWindow();
    result.snapshot_window = value.foreground_window;
    result.foreground_window = foreground;
    result.snapshot_process_id = value.foreground_process_id;
    result.direct = value.direct != 0;
    result.sensitive = value.sensitive != 0;
    result.age_ms = GetTickCount64() >= value.captured_tick
        ? GetTickCount64() - value.captured_tick
        : 0;
    DWORD process_id = 0;
    if (!foreground) {
      result.status = ReadStatus::NoForeground;
    } else if (foreground != value.foreground_window) {
      result.status = ReadStatus::ForegroundWindowMismatch;
    } else if (!GetWindowThreadProcessId(foreground, &process_id) || process_id == 0) {
      result.status = ReadStatus::ProcessUnavailable;
    } else if (process_id != value.foreground_process_id) {
      result.status = ReadStatus::ProcessMismatch;
    } else if (result.age_ms > kSnapshotTtlMs) {
      result.status = ReadStatus::Expired;
    } else {
      result.status = ReadStatus::Match;
    }
    result.foreground_process_id = process_id;
    if (diagnostics) *diagnostics = result;
    if (result.status != ReadStatus::Match) return false;
    *direct = value.direct != 0;
    *sensitive = value.sensitive != 0;
    return true;
  }

 private:
  HANDLE mapping_ = nullptr;
  const Snapshot* view_ = nullptr;
};

class Writer {
 public:
  Writer() {
    if (CacheName().empty()) return;
    mapping_ = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0,
                                  sizeof(Snapshot), CacheName().c_str());
    const bool already_exists = mapping_ && GetLastError() == ERROR_ALREADY_EXISTS;
    if (mapping_) view_ = static_cast<Snapshot*>(MapViewOfFile(mapping_, FILE_MAP_WRITE, 0, 0, sizeof(Snapshot)));
    if (!view_ && mapping_) { CloseHandle(mapping_); mapping_ = nullptr; }
    if (view_ && !already_exists) ZeroMemory(view_, sizeof(*view_));
  }
  ~Writer() {
    if (view_) UnmapViewOfFile(view_);
    if (mapping_) CloseHandle(mapping_);
  }
  Writer(const Writer&) = delete;
  Writer& operator=(const Writer&) = delete;

  void Publish(HWND foreground, DWORD process_id, bool direct, bool sensitive) {
    if (!view_) return;
    InterlockedIncrement(&view_->sequence);
    MemoryBarrier();
    view_->foreground_window = foreground;
    view_->foreground_process_id = process_id;
    view_->captured_tick = GetTickCount64();
    view_->direct = direct ? 1 : 0;
    view_->sensitive = sensitive ? 1 : 0;
    MemoryBarrier();
    InterlockedIncrement(&view_->sequence);
  }

 private:
  HANDLE mapping_ = nullptr;
  Snapshot* view_ = nullptr;
};

}  // namespace gy::input_scope_cache
