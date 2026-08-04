#pragma once

#include <windows.h>

#include <string>
#include <vector>

namespace gy::settings_file {
inline bool WriteBytes(HANDLE file, const void* bytes, DWORD count) {
  DWORD written = 0;
  return WriteFile(file, bytes, count, &written, nullptr) && written == count;
}

inline bool EnsureUnicodeIniFile(const std::wstring& path) {
  if (path.empty()) return false;

  HANDLE source = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                              nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (source == INVALID_HANDLE_VALUE) {
    if (GetLastError() != ERROR_FILE_NOT_FOUND) return false;
    source = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                         FILE_ATTRIBUTE_NORMAL, nullptr);
    if (source == INVALID_HANDLE_VALUE) return false;
    const wchar_t bom = 0xFEFF;
    const bool ok = WriteBytes(source, &bom, sizeof(bom));
    CloseHandle(source);
    return ok;
  }

  LARGE_INTEGER size{};
  const bool size_ok = GetFileSizeEx(source, &size) && size.QuadPart >= 0 && size.QuadPart <= 512 * 1024;
  if (!size_ok) {
    CloseHandle(source);
    return false;
  }
  if (size.QuadPart == 0) {
    CloseHandle(source);
    HANDLE empty = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, TRUNCATE_EXISTING,
                               FILE_ATTRIBUTE_NORMAL, nullptr);
    if (empty == INVALID_HANDLE_VALUE) return false;
    const wchar_t bom = 0xFEFF;
    const bool ok = WriteBytes(empty, &bom, sizeof(bom));
    CloseHandle(empty);
    return ok;
  }

  std::vector<unsigned char> raw(static_cast<size_t>(size.QuadPart));
  DWORD read = 0;
  const bool read_ok = ReadFile(source, raw.data(), static_cast<DWORD>(raw.size()), &read, nullptr) &&
                       read == raw.size();
  CloseHandle(source);
  if (!read_ok) return false;
  if (raw.size() >= 2 && raw[0] == 0xFF && raw[1] == 0xFE) return true;

  size_t offset = 0;
  UINT code_page = CP_ACP;
  if (raw.size() >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF) {
    offset = 3;
    code_page = CP_UTF8;
  }
  const int source_length = static_cast<int>(raw.size() - offset);
  const DWORD conversion_flags = code_page == CP_UTF8 ? MB_ERR_INVALID_CHARS : 0;
  const int wide_length = MultiByteToWideChar(code_page, conversion_flags,
                                               reinterpret_cast<const char*>(raw.data() + offset), source_length,
                                               nullptr, 0);
  if (wide_length <= 0) return false;
  std::wstring converted(static_cast<size_t>(wide_length), L'\0');
  if (MultiByteToWideChar(code_page, conversion_flags,
                          reinterpret_cast<const char*>(raw.data() + offset), source_length,
                          converted.data(), wide_length) != wide_length) return false;

  // Flush the profile API's cache before atomically replacing its backing file.
  WritePrivateProfileStringW(nullptr, nullptr, nullptr, path.c_str());
  const std::wstring temporary = path + L".utf16.tmp";
  HANDLE destination = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                                   FILE_ATTRIBUTE_NORMAL, nullptr);
  if (destination == INVALID_HANDLE_VALUE) return false;
  const wchar_t bom = 0xFEFF;
  const DWORD content_bytes = static_cast<DWORD>(converted.size() * sizeof(wchar_t));
  const bool write_ok = WriteBytes(destination, &bom, sizeof(bom)) &&
                        WriteBytes(destination, converted.data(), content_bytes) && FlushFileBuffers(destination);
  CloseHandle(destination);
  if (!write_ok) {
    DeleteFileW(temporary.c_str());
    return false;
  }
  if (!MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    DeleteFileW(temporary.c_str());
    return false;
  }
  WritePrivateProfileStringW(nullptr, nullptr, nullptr, path.c_str());
  return true;
}
}  // namespace gy::settings_file
