#include "ClipboardHistory.h"

#include <windows.h>

#include <algorithm>
#include <ctime>

namespace gy::clipboard_history {
namespace {

// 每行一条：<unix_ts>\t<escaped text>\n，文件按时间正序追加，最旧在最前。
// 转义只处理会破坏行结构的字符：\t \r \n \\。UTF-8 落盘，无 BOM。

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
  const int length = WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                                         nullptr, 0, nullptr, nullptr);
  if (length <= 0) return {};
  std::string out(static_cast<size_t>(length), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                      out.data(), length, nullptr, nullptr);
  return out;
}

std::wstring FromUtf8(const std::string& text) {
  if (text.empty()) return {};
  const int length = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                                         nullptr, 0);
  if (length <= 0) return {};
  std::wstring out(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      out.data(), length);
  return out;
}

// 密码管理器用来声明“不要进剪贴板历史”的两个公开格式。
// ExcludeClipboardContentFromMonitorProcessing：出现即排除（1Password 等）。
// CanIncludeInClipboardHistory：值为 0 表示排除（Windows 剪贴板历史约定）。
UINT ExcludeFormat() {
  static const UINT format = RegisterClipboardFormatW(L"ExcludeClipboardContentFromMonitorProcessing");
  return format;
}
UINT HistoryOptInFormat() {
  static const UINT format = RegisterClipboardFormatW(L"CanIncludeInClipboardHistory");
  return format;
}

bool WriteAll(const std::vector<Entry>& entries) {
  const std::wstring path = HistoryPath();
  if (path.empty()) return false;
  std::wstring wide;
  for (auto it = entries.rbegin(); it != entries.rend(); ++it) {  // 最旧的写最前
    wide += std::to_wstring(it->unix_time);
    wide += L'\t';
    wide += Escape(it->text);
    wide += L'\n';
  }
  const std::string utf8 = ToUtf8(wide);
  const std::wstring temp = path + L".tmp";
  HANDLE file = CreateFileW(temp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const bool ok = WriteFile(file, utf8.data(), static_cast<DWORD>(utf8.size()), &written, nullptr) &&
                  written == utf8.size();
  CloseHandle(file);
  if (!ok) {
    DeleteFileW(temp.c_str());
    return false;
  }
  return MoveFileExW(temp.c_str(), path.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
}

}  // namespace

std::wstring HistoryPath() {
  wchar_t root[MAX_PATH]{};
  if (!GetEnvironmentVariableW(L"LOCALAPPDATA", root, MAX_PATH)) return {};
  const std::wstring directory = std::wstring(root) + L"\\GYInput";
  CreateDirectoryW(directory.c_str(), nullptr);
  return directory + L"\\clipboard-history.tsv";
}

std::vector<Entry> ReadAll() {
  std::vector<Entry> entries;
  const std::wstring path = HistoryPath();
  if (path.empty()) return entries;
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return entries;
  LARGE_INTEGER size{};
  std::string bytes;
  if (GetFileSizeEx(file, &size) && size.QuadPart > 0 &&
      size.QuadPart <= static_cast<LONGLONG>(kMaxEntries) * (kMaxItemBytes + 64)) {
    bytes.resize(static_cast<size_t>(size.QuadPart));
    DWORD read = 0;
    if (!ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr) ||
        read != bytes.size()) {
      bytes.clear();
    }
  }
  CloseHandle(file);

  const std::wstring wide = FromUtf8(bytes);
  size_t begin = 0;
  while (begin < wide.size()) {
    const size_t end = wide.find(L'\n', begin);
    const std::wstring line = wide.substr(begin, end == std::wstring::npos ? end : end - begin);
    begin = end == std::wstring::npos ? wide.size() : end + 1;
    const size_t tab = line.find(L'\t');
    if (tab == std::wstring::npos) continue;
    Entry entry{};
    try {
      entry.unix_time = std::stoull(line.substr(0, tab));
    } catch (...) {
      continue;
    }
    entry.text = Unescape(line.substr(tab + 1));
    entries.push_back(std::move(entry));
  }
  // 文件正序存储，接口约定最新在前。
  std::reverse(entries.begin(), entries.end());
  return entries;
}

bool AppendFromClipboard() {
  if (!IsClipboardFormatAvailable(CF_UNICODETEXT)) return false;
  const UINT exclude = ExcludeFormat();
  if (exclude != 0 && IsClipboardFormatAvailable(exclude)) return false;

  // 复制发生的瞬间剪贴板常被源进程短暂占用，稍等重试几次。
  bool opened = false;
  for (int attempt = 0; attempt < 5 && !opened; ++attempt) {
    opened = OpenClipboard(nullptr) != 0;
    if (!opened) Sleep(10);
  }
  if (!opened) return false;

  bool allowed = true;
  std::wstring text;
  const UINT opt_in = HistoryOptInFormat();
  if (opt_in != 0) {
    if (HANDLE data = GetClipboardData(opt_in)) {
      if (const DWORD* value = static_cast<const DWORD*>(GlobalLock(data))) {
        allowed = *value != 0;
        GlobalUnlock(data);
      }
    }
  }
  if (allowed) {
    if (HANDLE data = GetClipboardData(CF_UNICODETEXT)) {
      if (const wchar_t* locked = static_cast<const wchar_t*>(GlobalLock(data))) {
        text.assign(locked, wcsnlen(locked, kMaxItemBytes / sizeof(wchar_t) + 2));
        GlobalUnlock(data);
      }
    }
  }
  CloseClipboard();
  if (!allowed || text.empty()) return false;

  const std::string utf8 = ToUtf8(text);
  if (utf8.empty() || utf8.size() > kMaxItemBytes) return false;  // 超限不入历史（设计 §0）

  std::vector<Entry> entries = ReadAll();
  if (!entries.empty() && entries.front().text == text) return false;  // 连续去重
  entries.insert(entries.begin(), Entry{static_cast<unsigned long long>(std::time(nullptr)), text});
  if (entries.size() > kMaxEntries) entries.resize(kMaxEntries);  // 先进后出
  return WriteAll(entries);
}

bool Clear() {
  const std::wstring path = HistoryPath();
  if (path.empty()) return false;
  DeleteFileW((path + L".tmp").c_str());
  return DeleteFileW(path.c_str()) != 0 || GetLastError() == ERROR_FILE_NOT_FOUND;
}

size_t Count() {
  return ReadAll().size();
}

}  // namespace gy::clipboard_history
