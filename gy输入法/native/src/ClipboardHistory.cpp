#include "ClipboardHistory.h"

#include <windows.h>
#include <objbase.h>
#include <objidl.h>
#include <gdiplus.h>

#include <algorithm>
#include <ctime>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

namespace gy::clipboard_history {
namespace {

// v4 adds a server-assigned immutable sequence after the SHA-256 field.
// PNG bytes are never embedded in either manifest; old rows remain readable.
constexpr ULONGLONG kMaxOutboxManifestBytes = 128ULL * 1024ULL * 1024ULL;

std::mutex g_suppression_mutex;
std::wstring g_remote_clipboard_text;
bool g_remote_clipboard_image = false;
ULONGLONG g_remote_clipboard_until = 0;

std::wstring RootDirectory() {
  wchar_t root[MAX_PATH]{};
  if (!GetEnvironmentVariableW(L"LOCALAPPDATA", root, MAX_PATH)) return {};
  const std::wstring directory = std::wstring(root) + L"\\GYInput";
  CreateDirectoryW(directory.c_str(), nullptr);
  return directory;
}

std::wstring ImagesDirectory() {
  const std::wstring root = RootDirectory();
  if (root.empty()) return {};
  const std::wstring directory = root + L"\\clipboard-assets";
  CreateDirectoryW(directory.c_str(), nullptr);
  return directory;
}

std::wstring ImagePath(const std::wstring& id) {
  const std::wstring directory = ImagesDirectory();
  return directory.empty() || id.empty() ? std::wstring{} : directory + L"\\" + id + L".png";
}

std::wstring CreateEntryId() {
  GUID guid{};
  if (CoCreateGuid(&guid) != S_OK) return {};
  wchar_t buffer[40]{};
  if (StringFromGUID2(guid, buffer, 40) != 39) return {};
  return std::wstring(buffer + 1, 36);
}

bool IsSuppressedRemoteText(const std::wstring& text) {
  std::lock_guard<std::mutex> lock(g_suppression_mutex);
  if (GetTickCount64() > g_remote_clipboard_until) {
    g_remote_clipboard_text.clear();
    g_remote_clipboard_image = false;
    return false;
  }
  return text == g_remote_clipboard_text;
}

bool TakeSuppressedRemoteImage() {
  std::lock_guard<std::mutex> lock(g_suppression_mutex);
  if (GetTickCount64() > g_remote_clipboard_until || !g_remote_clipboard_image) return false;
  g_remote_clipboard_image = false;
  return true;
}

void SuppressRemoteText(const std::wstring& text) {
  std::lock_guard<std::mutex> lock(g_suppression_mutex);
  g_remote_clipboard_text = text;
  g_remote_clipboard_image = false;
  g_remote_clipboard_until = GetTickCount64() + 2000;
}

void SuppressRemoteImage() {
  std::lock_guard<std::mutex> lock(g_suppression_mutex);
  g_remote_clipboard_text.clear();
  g_remote_clipboard_image = true;
  g_remote_clipboard_until = GetTickCount64() + 2000;
}

std::wstring Escape(const std::wstring& text) {
  std::wstring out;
  out.reserve(text.size());
  for (const wchar_t ch : text) {
    switch (ch) {
      case L'\\': out += L"\\\\"; break;
      case L'\t': out += L"\\t"; break;
      case L'\r': out += L"\\r"; break;
      case L'\n': out += L"\\n"; break;
      default: out += ch; break;
    }
  }
  return out;
}

std::wstring Unescape(const std::wstring& text) {
  std::wstring out;
  out.reserve(text.size());
  for (size_t i = 0; i < text.size(); ++i) {
    if (text[i] == L'\\' && i + 1 < text.size()) {
      const wchar_t next = text[i + 1];
      if (next == L'\\') { out += L'\\'; ++i; continue; }
      if (next == L't') { out += L'\t'; ++i; continue; }
      if (next == L'r') { out += L'\r'; ++i; continue; }
      if (next == L'n') { out += L'\n'; ++i; continue; }
    }
    out += text[i];
  }
  return out;
}

std::string ToUtf8(const std::wstring& text) {
  if (text.empty()) return {};
  const int length = WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  if (length <= 0) return {};
  std::string out(static_cast<size_t>(length), '\0');
  if (!WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), out.data(), length, nullptr, nullptr)) return {};
  return out;
}

std::wstring FromUtf8(const std::string& text) {
  if (text.empty()) return {};
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (length <= 0) return {};
  std::wstring out(static_cast<size_t>(length), L'\0');
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), out.data(), length)) return {};
  return out;
}

UINT ExcludeFormat() { static const UINT format = RegisterClipboardFormatW(L"ExcludeClipboardContentFromMonitorProcessing"); return format; }
UINT HistoryOptInFormat() { static const UINT format = RegisterClipboardFormatW(L"CanIncludeInClipboardHistory"); return format; }

ULONG_PTR GdiPlusToken() {
  static const ULONG_PTR token = []() {
    Gdiplus::GdiplusStartupInput startup{};
    ULONG_PTR value = 0;
    return Gdiplus::GdiplusStartup(&value, &startup, nullptr) == Gdiplus::Ok ? value : static_cast<ULONG_PTR>(0);
  }();
  return token;
}

bool PngEncoder(CLSID* result) {
  if (!result || !GdiPlusToken()) return false;
  UINT count = 0, bytes = 0;
  if (Gdiplus::GetImageEncodersSize(&count, &bytes) != Gdiplus::Ok || bytes == 0) return false;
  std::vector<BYTE> buffer(bytes);
  auto* codecs = reinterpret_cast<Gdiplus::ImageCodecInfo*>(buffer.data());
  if (Gdiplus::GetImageEncoders(count, bytes, codecs) != Gdiplus::Ok) return false;
  for (UINT i = 0; i < count; ++i) {
    if (codecs[i].MimeType && wcscmp(codecs[i].MimeType, L"image/png") == 0) { *result = codecs[i].Clsid; return true; }
  }
  return false;
}

bool EncodeBitmapAsPng(HBITMAP bitmap, std::string* png) {
  if (!bitmap || !png || !GdiPlusToken()) return false;
  png->clear();
  Gdiplus::Bitmap image(bitmap, nullptr);
  if (image.GetLastStatus() != Gdiplus::Ok) return false;
  CLSID encoder{};
  if (!PngEncoder(&encoder)) return false;
  IStream* stream = nullptr;
  if (CreateStreamOnHGlobal(nullptr, TRUE, &stream) != S_OK) return false;
  const Gdiplus::Status status = image.Save(stream, &encoder, nullptr);
  HGLOBAL memory = nullptr;
  const bool got_memory = status == Gdiplus::Ok && GetHGlobalFromStream(stream, &memory) == S_OK;
  SIZE_T size = got_memory && memory ? GlobalSize(memory) : 0;
  const void* data = size > 0 ? GlobalLock(memory) : nullptr;
  if (data && size <= kMaxImageBytes) png->assign(static_cast<const char*>(data), size);
  if (data) GlobalUnlock(memory);
  stream->Release();
  return !png->empty();
}

HBITMAP BitmapFromDib(HANDLE handle) {
  if (!handle) return nullptr;
  const BYTE* base = static_cast<const BYTE*>(GlobalLock(handle));
  if (!base) return nullptr;
  const auto* header = reinterpret_cast<const BITMAPINFOHEADER*>(base);
  HBITMAP bitmap = nullptr;
  if (header->biSize >= sizeof(BITMAPINFOHEADER) && header->biSize <= 4096 && header->biWidth > 0 && header->biHeight != 0) {
    size_t palette = 0;
    if (header->biBitCount <= 8) palette = static_cast<size_t>(header->biClrUsed ? header->biClrUsed : (1u << header->biBitCount)) * sizeof(RGBQUAD);
    else if (header->biCompression == BI_BITFIELDS && header->biSize == sizeof(BITMAPINFOHEADER)) palette = 3 * sizeof(DWORD);
    const BYTE* bits = base + header->biSize + palette;
    HDC dc = GetDC(nullptr);
    bitmap = CreateDIBitmap(dc, header, CBM_INIT, bits, reinterpret_cast<const BITMAPINFO*>(base), DIB_RGB_COLORS);
    ReleaseDC(nullptr, dc);
  }
  GlobalUnlock(handle);
  return bitmap;
}

bool CaptureClipboardPng(std::string* png) {
  if (!png) return false;
  HBITMAP bitmap = static_cast<HBITMAP>(GetClipboardData(CF_BITMAP));
  if (bitmap) return EncodeBitmapAsPng(bitmap, png);
  HANDLE dib = GetClipboardData(CF_DIBV5);
  if (!dib) dib = GetClipboardData(CF_DIB);
  HBITMAP converted = BitmapFromDib(dib);
  if (!converted) return false;
  const bool ok = EncodeBitmapAsPng(converted, png);
  DeleteObject(converted);
  return ok;
}

bool WriteBytesAtomically(const std::wstring& path, const std::string& bytes) {
  if (path.empty() || bytes.empty() || bytes.size() > kMaxImageBytes) return false;
  const std::wstring temporary = path + L".tmp";
  HANDLE file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const bool ok = WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr) && written == bytes.size();
  CloseHandle(file);
  if (!ok) { DeleteFileW(temporary.c_str()); return false; }
  return MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
}

bool WriteAll(const std::vector<Entry>& entries) {
  const std::wstring path = HistoryPath();
  if (path.empty()) return false;
  std::wstring wide;
  for (auto it = entries.rbegin(); it != entries.rend(); ++it) {
    if (it->id.empty()) return false;
    wide += it->id + L"\t" + std::to_wstring(it->unix_time) + L"\t" + (it->pending_upload ? L"1" : L"0") + L"\t";
    wide += it->kind == EntryKind::PngImage ? L"I\t" : L"T\t";
    wide += Escape(it->text) + L"\t" + Escape(it->image_sha256) + L"\t" + std::to_wstring(it->sync_sequence) + L"\n";
  }
  const std::string utf8 = ToUtf8(wide);
  const std::wstring temporary = path + L".tmp";
  HANDLE file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const bool ok = WriteFile(file, utf8.data(), static_cast<DWORD>(utf8.size()), &written, nullptr) && written == utf8.size();
  CloseHandle(file);
  if (!ok) { DeleteFileW(temporary.c_str()); return false; }
  return MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
}

bool WriteOutbox(const std::vector<Entry>& entries) {
  const std::wstring path = OutboxPath();
  if (path.empty()) return false;
  if (entries.empty()) {
    DeleteFileW((path + L".tmp").c_str());
    return DeleteFileW(path.c_str()) != 0 || GetLastError() == ERROR_FILE_NOT_FOUND;
  }
  std::wstring wide;
  for (auto it = entries.rbegin(); it != entries.rend(); ++it) {
    if (it->id.empty()) return false;
    wide += it->id + L"\t" + std::to_wstring(it->unix_time) + L"\t1\t";
    wide += it->kind == EntryKind::PngImage ? L"I\t" : L"T\t";
    wide += Escape(it->text) + L"\t" + Escape(it->image_sha256) + L"\t" + std::to_wstring(it->sync_sequence) + L"\n";
  }
  const std::string utf8 = ToUtf8(wide);
  const std::wstring temporary = path + L".tmp";
  HANDLE file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const bool ok = WriteFile(file, utf8.data(), static_cast<DWORD>(utf8.size()), &written, nullptr) && written == utf8.size();
  CloseHandle(file);
  if (!ok) { DeleteFileW(temporary.c_str()); return false; }
  return MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
}

}  // namespace

#ifdef GY_TESTING
namespace testing {

bool EncodeBitmapAsPng(HBITMAP bitmap, std::string* png) {
  return ::gy::clipboard_history::EncodeBitmapAsPng(bitmap, png);
}

}  // namespace testing
#endif

std::wstring HistoryPath() {
  const std::wstring directory = RootDirectory();
  return directory.empty() ? std::wstring{} : directory + L"\\clipboard-history.tsv";
}

std::wstring OutboxPath() {
  const std::wstring directory = RootDirectory();
  return directory.empty() ? std::wstring{} : directory + L"\\clipboard-outbox.tsv";
}

std::vector<Entry> ReadAll() {
  std::vector<Entry> entries;
  const std::wstring path = HistoryPath();
  if (path.empty()) return entries;
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return entries;
  LARGE_INTEGER size{};
  std::string bytes;
  if (GetFileSizeEx(file, &size) && size.QuadPart > 0 && size.QuadPart <= static_cast<LONGLONG>(kMaxEntries) * (kMaxItemBytes + 256)) {
    bytes.resize(static_cast<size_t>(size.QuadPart));
    DWORD read = 0;
    if (!ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr) || read != bytes.size()) bytes.clear();
  }
  CloseHandle(file);
  const std::wstring wide = FromUtf8(bytes);
  size_t begin = 0;
  while (begin < wide.size()) {
    const size_t end = wide.find(L'\n', begin);
    const std::wstring line = wide.substr(begin, end == std::wstring::npos ? std::wstring::npos : end - begin);
    begin = end == std::wstring::npos ? wide.size() : end + 1;
    const size_t first = line.find(L'\t');
    if (first == std::wstring::npos) continue;
    Entry entry{};
    const size_t second = line.find(L'\t', first + 1);
    const size_t third = second == std::wstring::npos ? std::wstring::npos : line.find(L'\t', second + 1);
    if (third == std::wstring::npos) {
      try { entry.unix_time = std::stoull(line.substr(0, first)); } catch (...) { continue; }
      entry.id = CreateEntryId();
      entry.text = Unescape(line.substr(first + 1));
      entry.pending_upload = !entry.id.empty();
    } else {
      entry.id = line.substr(0, first);
      try { entry.unix_time = std::stoull(line.substr(first + 1, second - first - 1)); } catch (...) { continue; }
      const std::wstring pending = line.substr(second + 1, third - second - 1);
      if (entry.id.empty() || (pending != L"0" && pending != L"1")) continue;
      entry.pending_upload = pending == L"1";
      const size_t fourth = line.find(L'\t', third + 1);
      const size_t fifth = fourth == std::wstring::npos ? std::wstring::npos : line.find(L'\t', fourth + 1);
      if (fourth == std::wstring::npos || fifth == std::wstring::npos) {
        entry.text = Unescape(line.substr(third + 1));  // v2 text
      } else {
        const std::wstring kind = line.substr(third + 1, fourth - third - 1);
        if (kind == L"T") entry.kind = EntryKind::Text;
        else if (kind == L"I") entry.kind = EntryKind::PngImage;
        else continue;
        entry.text = Unescape(line.substr(fourth + 1, fifth - fourth - 1));
        const size_t sixth = line.find(L'\t', fifth + 1);
        entry.image_sha256 = Unescape(line.substr(fifth + 1,
            sixth == std::wstring::npos ? std::wstring::npos : sixth - fifth - 1));
        if (sixth != std::wstring::npos) {
          try { entry.sync_sequence = std::stoull(line.substr(sixth + 1)); }
          catch (...) { continue; }
        }
      }
    }
    if ((entry.kind == EntryKind::Text && entry.text.empty()) || (entry.kind == EntryKind::PngImage && entry.id.empty())) continue;
    entries.push_back(std::move(entry));
  }
  std::reverse(entries.begin(), entries.end());
  return entries;
}

std::vector<Entry> ReadPendingOutbox() {
  std::vector<Entry> entries;
  const std::wstring path = OutboxPath();
  if (path.empty()) return entries;
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return entries;
  LARGE_INTEGER size{};
  std::string bytes;
  if (GetFileSizeEx(file, &size) && size.QuadPart > 0 && size.QuadPart <= static_cast<LONGLONG>(kMaxOutboxManifestBytes)) {
    bytes.resize(static_cast<size_t>(size.QuadPart));
    DWORD read = 0;
    if (!ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr) || read != bytes.size()) bytes.clear();
  }
  CloseHandle(file);
  const std::wstring wide = FromUtf8(bytes);
  size_t begin = 0;
  while (begin < wide.size()) {
    const size_t end = wide.find(L'\n', begin);
    const std::wstring line = wide.substr(begin, end == std::wstring::npos ? std::wstring::npos : end - begin);
    begin = end == std::wstring::npos ? wide.size() : end + 1;
    const size_t first = line.find(L'\t');
    const size_t second = first == std::wstring::npos ? std::wstring::npos : line.find(L'\t', first + 1);
    const size_t third = second == std::wstring::npos ? std::wstring::npos : line.find(L'\t', second + 1);
    const size_t fourth = third == std::wstring::npos ? std::wstring::npos : line.find(L'\t', third + 1);
    const size_t fifth = fourth == std::wstring::npos ? std::wstring::npos : line.find(L'\t', fourth + 1);
    if (fifth == std::wstring::npos) continue;
    Entry entry{};
    entry.id = line.substr(0, first);
    const std::wstring pending = line.substr(second + 1, third - second - 1);
    const std::wstring kind = line.substr(third + 1, fourth - third - 1);
    if (entry.id.empty() || pending != L"1" || (kind != L"T" && kind != L"I")) continue;
    try { entry.unix_time = std::stoull(line.substr(first + 1, second - first - 1)); } catch (...) { continue; }
    entry.pending_upload = true;
    entry.kind = kind == L"I" ? EntryKind::PngImage : EntryKind::Text;
    const size_t sixth = line.find(L'\t', fifth + 1);
    entry.text = Unescape(line.substr(fourth + 1, fifth - fourth - 1));
    entry.image_sha256 = Unescape(line.substr(fifth + 1,
        sixth == std::wstring::npos ? std::wstring::npos : sixth - fifth - 1));
    if (sixth != std::wstring::npos) {
      try { entry.sync_sequence = std::stoull(line.substr(sixth + 1)); } catch (...) { continue; }
    }
    if ((entry.kind == EntryKind::Text && entry.text.empty()) ||
        (entry.kind == EntryKind::PngImage && entry.id.empty())) continue;
    entries.push_back(std::move(entry));
  }
  std::reverse(entries.begin(), entries.end());  // oldest first for upload.
  return entries;
}

bool MigratePendingHistoryToOutbox() {
  std::vector<Entry> history = ReadAll();
  std::vector<Entry> outbox = ReadPendingOutbox();
  std::unordered_set<std::wstring> ids;
  for (const auto& entry : outbox) ids.insert(entry.id);
  bool changed = false;
  for (auto it = history.rbegin(); it != history.rend(); ++it) {
    if (it->pending_upload && ids.insert(it->id).second) {
      outbox.push_back(*it);
      changed = true;
    }
  }
  return !changed || WriteOutbox(outbox);
}

bool AcknowledgeUploaded(const std::wstring& id, unsigned long long sync_sequence) {
  if (id.empty() || sync_sequence == 0) return false;
  // Persist confirmation before discarding the retry record.  If the process
  // stops between these writes, the outbox can resend the same ID and Keep's
  // idempotent upsert returns the same authoritative sequence.  Reversing the
  // order would make a local write failure erase the only durable retry path.
  std::vector<Entry> history = ReadAll();
  bool changed = false;
  for (auto& entry : history) {
    if (entry.id == id) {
      entry.pending_upload = false;
      entry.sync_sequence = sync_sequence;
      changed = true;
    }
  }
  if (changed && !WriteAll(history)) return false;

  std::vector<Entry> outbox = ReadPendingOutbox();
  const size_t before = outbox.size();
  outbox.erase(std::remove_if(outbox.begin(), outbox.end(), [&](const Entry& entry) {
    return entry.id == id;
  }), outbox.end());
  return outbox.size() == before || WriteOutbox(outbox);
}

bool ApplyConfirmedChanges(const std::vector<RemoteChange>& changes) {
  std::vector<Entry> merged = ReadAll();
  for (const auto& change : changes) {
    const Entry& incoming = change.entry;
    if (incoming.id.empty() || incoming.sync_sequence == 0) return false;
    if (change.kind == RemoteChangeKind::Delete) {
      merged.erase(std::remove_if(merged.begin(), merged.end(), [&](const Entry& current) {
        return current.id == incoming.id;
      }), merged.end());
      continue;
    }
    if (incoming.id.empty() || incoming.sync_sequence == 0 ||
        (incoming.kind == EntryKind::Text && incoming.text.empty())) return false;
    bool found = false;
    for (auto& current : merged) {
      if (current.id == incoming.id) {
        current = incoming;
        found = true;
        break;
      }
    }
    if (!found) merged.push_back(incoming);
  }
  std::stable_sort(merged.begin(), merged.end(), [](const Entry& left, const Entry& right) {
    if (left.pending_upload != right.pending_upload) return left.pending_upload;
    if (left.sync_sequence != right.sync_sequence) return left.sync_sequence > right.sync_sequence;
    return left.unix_time > right.unix_time;
  });
  if (merged.size() > kMaxEntries) merged.resize(kMaxEntries);
  return WriteAll(merged);
}

bool ReplaceConfirmedSnapshot(const std::vector<Entry>& confirmed) {
  std::vector<Entry> merged;
  merged.reserve(confirmed.size() + kMaxEntries);
  std::unordered_set<std::wstring> confirmed_ids;
  for (const auto& incoming : confirmed) {
    if (incoming.id.empty() || incoming.sync_sequence == 0 ||
        (incoming.kind == EntryKind::Text && incoming.text.empty())) return false;
    if (confirmed_ids.insert(incoming.id).second) merged.push_back(incoming);
  }

  // A lost ACK is harmless: if Keep's snapshot already contains the ID, the
  // authoritative confirmed copy wins while the durable outbox retries later.
  for (const auto& local : ReadAll()) {
    if (local.pending_upload && confirmed_ids.insert(local.id).second) merged.push_back(local);
  }
  std::stable_sort(merged.begin(), merged.end(), [](const Entry& left, const Entry& right) {
    if (left.pending_upload != right.pending_upload) return left.pending_upload;
    if (left.sync_sequence != right.sync_sequence) return left.sync_sequence > right.sync_sequence;
    return left.unix_time > right.unix_time;
  });
  if (merged.size() > kMaxEntries) merged.resize(kMaxEntries);
  return WriteAll(merged);
}

bool AppendFromClipboard() {
  const UINT exclude = ExcludeFormat();
  if (exclude != 0 && IsClipboardFormatAvailable(exclude)) return false;
  bool opened = false;
  for (int attempt = 0; attempt < 5 && !opened; ++attempt) { opened = OpenClipboard(nullptr) != 0; if (!opened) Sleep(10); }
  if (!opened) return false;

  bool allowed = true;
  const UINT opt_in = HistoryOptInFormat();
  if (opt_in != 0) {
    if (HANDLE data = GetClipboardData(opt_in)) {
      if (const DWORD* value = static_cast<const DWORD*>(GlobalLock(data))) { allowed = *value != 0; GlobalUnlock(data); }
    }
  }
  std::wstring text;
  std::string png;
  EntryKind kind = EntryKind::Text;
  if (allowed && IsClipboardFormatAvailable(CF_UNICODETEXT)) {
    if (HANDLE data = GetClipboardData(CF_UNICODETEXT)) {
      if (const wchar_t* locked = static_cast<const wchar_t*>(GlobalLock(data))) { text.assign(locked, wcsnlen(locked, kMaxItemBytes / sizeof(wchar_t) + 2)); GlobalUnlock(data); }
    }
  } else if (allowed) {
    kind = EntryKind::PngImage;
    CaptureClipboardPng(&png);
  }
  CloseClipboard();
  if (!allowed) return false;

  if (kind == EntryKind::Text) {
    if (text.empty() || IsSuppressedRemoteText(text)) return false;
    const std::string utf8 = ToUtf8(text);
    if (utf8.empty() || utf8.size() > kMaxItemBytes) return false;
    std::vector<Entry> entries = ReadAll();
    if (!entries.empty() && entries.front().kind == EntryKind::Text && entries.front().text == text) return false;
    const std::wstring id = CreateEntryId();
    if (id.empty()) return false;
    const Entry captured{id, static_cast<unsigned long long>(std::time(nullptr)), text, true};
    std::vector<Entry> outbox = ReadPendingOutbox();
    outbox.push_back(captured);  // outbox is oldest first
    if (!WriteOutbox(outbox)) return false;
    entries.insert(entries.begin(), captured);
    if (entries.size() > kMaxEntries) entries.resize(kMaxEntries);
    return WriteAll(entries);
  }

  if (png.empty() || png.size() > kMaxImageBytes || TakeSuppressedRemoteImage()) return false;
  const std::wstring id = CreateEntryId();
  if (id.empty() || !WriteBytesAtomically(ImagePath(id), png)) return false;
  std::vector<Entry> entries = ReadAll();
  const Entry captured{id, static_cast<unsigned long long>(std::time(nullptr)), L"[图片]", true, EntryKind::PngImage};
  std::vector<Entry> outbox = ReadPendingOutbox();
  outbox.push_back(captured);  // outbox is oldest first
  if (!WriteOutbox(outbox)) return false;
  entries.insert(entries.begin(), captured);
  if (entries.size() > kMaxEntries) entries.resize(kMaxEntries);
  return WriteAll(entries);
}

bool ReplaceAll(const std::vector<Entry>& entries) {
  if (entries.size() > kMaxEntries) return false;
  for (const Entry& entry : entries) {
    if (entry.id.empty() || (entry.kind == EntryKind::Text && entry.text.empty())) return false;
    if (entry.kind == EntryKind::PngImage) {
      std::string png;
      if (!ReadImagePng(entry, &png)) return false;
    }
  }
  return WriteAll(entries);
}

bool ReadImagePng(const Entry& entry, std::string* png) {
  if (!png || entry.kind != EntryKind::PngImage) return false;
  png->clear();
  const std::wstring path = ImagePath(entry.id);
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  LARGE_INTEGER size{};
  if (!GetFileSizeEx(file, &size) || size.QuadPart <= 0 || size.QuadPart > static_cast<LONGLONG>(kMaxImageBytes)) { CloseHandle(file); return false; }
  png->resize(static_cast<size_t>(size.QuadPart));
  DWORD read = 0;
  const bool ok = ReadFile(file, png->data(), static_cast<DWORD>(png->size()), &read, nullptr) && read == png->size();
  CloseHandle(file);
  if (!ok) png->clear();
  return ok;
}

bool SaveImagePngFromKeep(const Entry& entry, const std::string& png) {
  return entry.kind == EntryKind::PngImage && !entry.id.empty() && WriteBytesAtomically(ImagePath(entry.id), png);
}

bool SetSystemClipboardTextFromKeep(const std::wstring& text) {
  if (text.empty()) return false;
  bool opened = false;
  for (int attempt = 0; attempt < 5 && !opened; ++attempt) { opened = OpenClipboard(nullptr) != 0; if (!opened) Sleep(10); }
  if (!opened || !EmptyClipboard()) { if (opened) CloseClipboard(); return false; }
  const size_t bytes = (text.size() + 1) * sizeof(wchar_t);
  HGLOBAL data = GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (!data) { CloseClipboard(); return false; }
  void* locked = GlobalLock(data);
  if (!locked) { GlobalFree(data); CloseClipboard(); return false; }
  memcpy(locked, text.c_str(), bytes); GlobalUnlock(data);
  SuppressRemoteText(text);
  if (!SetClipboardData(CF_UNICODETEXT, data)) { GlobalFree(data); CloseClipboard(); return false; }
  CloseClipboard();
  return true;
}

bool SetSystemClipboardImageFromKeep(const Entry& entry) {
  std::string png;
  if (!ReadImagePng(entry, &png) || !GdiPlusToken()) return false;
  IStream* stream = nullptr;
  if (CreateStreamOnHGlobal(nullptr, TRUE, &stream) != S_OK) return false;
  ULONG written = 0;
  const bool stream_ok = stream->Write(png.data(), static_cast<ULONG>(png.size()), &written) == S_OK && written == png.size();
  LARGE_INTEGER zero{};
  if (!stream_ok || stream->Seek(zero, STREAM_SEEK_SET, nullptr) != S_OK) { stream->Release(); return false; }
  Gdiplus::Bitmap image(stream);
  HBITMAP bitmap = nullptr;
  const bool bitmap_ok = image.GetLastStatus() == Gdiplus::Ok && image.GetHBITMAP(Gdiplus::Color::White, &bitmap) == Gdiplus::Ok && bitmap;
  stream->Release();
  if (!bitmap_ok) return false;
  bool opened = false;
  for (int attempt = 0; attempt < 5 && !opened; ++attempt) { opened = OpenClipboard(nullptr) != 0; if (!opened) Sleep(10); }
  if (!opened || !EmptyClipboard()) { if (opened) CloseClipboard(); DeleteObject(bitmap); return false; }
  SuppressRemoteImage();
  if (!SetClipboardData(CF_BITMAP, bitmap)) { DeleteObject(bitmap); CloseClipboard(); return false; }
  CloseClipboard();
  return true;
}

bool Clear() {
  const std::wstring path = HistoryPath();
  if (path.empty()) return false;
  DeleteFileW((path + L".tmp").c_str());
  const std::wstring outbox = OutboxPath();
  DeleteFileW((outbox + L".tmp").c_str());
  if (!outbox.empty()) DeleteFileW(outbox.c_str());
  const std::wstring images = ImagesDirectory();
  WIN32_FIND_DATAW found{};
  HANDLE search = FindFirstFileW((images + L"\\*.png").c_str(), &found);
  if (search != INVALID_HANDLE_VALUE) {
    do { DeleteFileW((images + L"\\" + found.cFileName).c_str()); } while (FindNextFileW(search, &found));
    FindClose(search);
  }
  return DeleteFileW(path.c_str()) != 0 || GetLastError() == ERROR_FILE_NOT_FOUND;
}

size_t Count() { return ReadAll().size(); }

}  // namespace gy::clipboard_history
