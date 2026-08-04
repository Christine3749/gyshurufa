#pragma once

#include <algorithm>
#include <string>

#include <windows.h>

#include "SettingsFile.h"

namespace gy::input_mode {

constexpr int kSimplified = 0;
constexpr int kTraditional = 1;
constexpr int kEnglish = 2;

constexpr int Normalize(int mode) { return std::clamp(mode, kSimplified, kEnglish); }
constexpr bool IsEnglish(int mode) { return Normalize(mode) == kEnglish; }

inline std::wstring SettingsPath() {
  wchar_t root[MAX_PATH]{};
  if (!GetEnvironmentVariableW(L"LOCALAPPDATA", root, MAX_PATH)) return {};
  const std::wstring directory = std::wstring(root) + L"\\GYInput";
  CreateDirectoryW(directory.c_str(), nullptr);
  return directory + L"\\settings.ini";
}

// Registry is the authoritative live state: TSF is loaded independently into
// every target process, while the legacy INI API may serve a process-local
// cached value after a fast focus switch. The INI remains a backup/export
// format and is written alongside the registry for compatibility.
inline int Read() {
  DWORD value = kSimplified;
  DWORD size = sizeof(value);
  if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\GYInput", L"InputMode",
                   RRF_RT_REG_DWORD, nullptr, &value, &size) == ERROR_SUCCESS) {
    return Normalize(static_cast<int>(value));
  }

  const std::wstring path = SettingsPath();
  return Normalize(path.empty() ? kSimplified
                                : static_cast<int>(GetPrivateProfileIntW(L"Input", L"Mode", kSimplified, path.c_str())));
}

inline void Write(int mode) {
  mode = Normalize(mode);
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\GYInput", 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
    const DWORD value = static_cast<DWORD>(mode);
    RegSetValueExW(key, L"InputMode", 0, REG_DWORD,
                   reinterpret_cast<const BYTE*>(&value), sizeof(value));
    RegCloseKey(key);
  }

  const std::wstring path = SettingsPath();
  if (!path.empty() && gy::settings_file::EnsureUnicodeIniFile(path)) {
    WritePrivateProfileStringW(L"Input", L"Mode", std::to_wstring(mode).c_str(), path.c_str());
  }
}

}  // namespace gy::input_mode
