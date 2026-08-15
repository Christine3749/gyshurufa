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
constexpr int NormalizeChinese(int mode) {
  return Normalize(mode) == kTraditional ? kTraditional : kSimplified;
}
constexpr bool IsEnglish(int mode) { return Normalize(mode) == kEnglish; }

inline std::wstring SettingsPath() {
  wchar_t root[MAX_PATH]{};
  if (!GetEnvironmentVariableW(L"LOCALAPPDATA", root, MAX_PATH)) return {};
  const std::wstring directory = std::wstring(root) + L"\\GYInput";
  CreateDirectoryW(directory.c_str(), nullptr);
  return directory + L"\\settings.ini";
}

inline bool CanWriteRegistryState() {
  HKEY key = nullptr;
  const LSTATUS result = RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\GYInput", 0,
                                       KEY_SET_VALUE, &key);
  if (result != ERROR_SUCCESS) return false;
  RegCloseKey(key);
  return true;
}

inline int ReadIniModeRaw(const wchar_t* value_name, int fallback) {
  const std::wstring path = SettingsPath();
  return path.empty() ? fallback : static_cast<int>(
      GetPrivateProfileIntW(L"Input", value_name, fallback, path.c_str()));
}

inline int ReadIniMode(const wchar_t* value_name, int fallback) {
  return Normalize(ReadIniModeRaw(value_name, fallback));
}

#if defined(GY_TESTING)
// Test binaries must never change a developer's or beta tester's active input
// mode. The temporary test Host and its controller run in separate processes,
// so share only a file in their isolated LOCALAPPDATA rather than touching
// HKCU or the user's settings.ini. Production DLL/Host builds do not compile
// this branch.
inline std::wstring TestModePath() {
  const std::wstring settings = SettingsPath();
  const size_t slash = settings.find_last_of(L"\\/");
  return slash == std::wstring::npos ? std::wstring{} :
      settings.substr(0, slash + 1) + L"test-input-mode.ini";
}

inline int ReadTestMode(const wchar_t* value_name, int fallback) {
  const std::wstring path = TestModePath();
  return Normalize(path.empty() ? fallback : static_cast<int>(
      GetPrivateProfileIntW(L"Input", value_name, fallback, path.c_str())));
}

inline bool WriteTestMode(const wchar_t* value_name, int mode) {
  const std::wstring path = TestModePath();
  return !path.empty() && WritePrivateProfileStringW(
      L"Input", value_name, std::to_wstring(Normalize(mode)).c_str(), path.c_str()) != FALSE &&
      static_cast<int>(GetPrivateProfileIntW(L"Input", value_name, MAXDWORD, path.c_str())) == Normalize(mode);
}
#endif

// Registry is the preferred live state because TSF is loaded independently
// into every target process. A previous elevated installer can leave an old
// HKCU key readable but not writable by the interactive user; in that case a
// stale registry value must never override the user's writable local setting.
inline int Read() {
#if defined(GY_HEALTH_READONLY_INPUT_MODE)
  // The installed offline health checker validates data loading only. It must
  // never observe or alter the person's cross-application input selection.
  return kSimplified;
#elif defined(GY_TESTING)
  return ReadTestMode(L"Mode", kSimplified);
#else
  if (CanWriteRegistryState()) {
    DWORD value = kSimplified;
    DWORD size = sizeof(value);
    if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\GYInput", L"InputMode",
                     RRF_RT_REG_DWORD, nullptr, &value, &size) == ERROR_SUCCESS) {
      return Normalize(static_cast<int>(value));
    }
  }
  return ReadIniMode(L"Mode", kSimplified);
#endif
}

// EN is a persistent global mode, while Shift still needs a reliable Chinese
// destination. Store that destination independently so a new TSF instance
// does not accidentally fall back from 繁体 to 简体 when the user leaves EN.
inline int ReadLastChineseMode() {
#if defined(GY_HEALTH_READONLY_INPUT_MODE)
  return kSimplified;
#elif defined(GY_TESTING)
  return NormalizeChinese(ReadTestMode(L"LastChineseMode", kSimplified));
#else
  if (CanWriteRegistryState()) {
    DWORD value = kSimplified;
    DWORD size = sizeof(value);
    if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\GYInput", L"LastChineseMode",
                     RRF_RT_REG_DWORD, nullptr, &value, &size) == ERROR_SUCCESS) {
      return NormalizeChinese(static_cast<int>(value));
    }
  }
  return NormalizeChinese(ReadIniMode(L"LastChineseMode", kSimplified));
#endif
}

inline bool Write(int mode) {
  mode = Normalize(mode);
#if defined(GY_HEALTH_READONLY_INPUT_MODE)
  // A health executable has no authority to change global input mode.
  (void)mode;
  return true;
#elif defined(GY_TESTING)
  return WriteTestMode(L"Mode", mode) &&
      (IsEnglish(mode) || WriteTestMode(L"LastChineseMode", NormalizeChinese(mode)));
#else
  const std::wstring path = SettingsPath();
  if (path.empty() || !gy::settings_file::EnsureUnicodeIniFile(path)) return false;
  const int previous_ini_mode = ReadIniMode(L"Mode", kSimplified);
  const int previous_ini_chinese = NormalizeChinese(ReadIniMode(L"LastChineseMode", kSimplified));
  const auto restore_ini = [&] {
    WritePrivateProfileStringW(L"Input", L"Mode", std::to_wstring(previous_ini_mode).c_str(), path.c_str());
    WritePrivateProfileStringW(L"Input", L"LastChineseMode",
                               std::to_wstring(previous_ini_chinese).c_str(), path.c_str());
  };

  if (!WritePrivateProfileStringW(L"Input", L"Mode", std::to_wstring(mode).c_str(), path.c_str()) ||
      (!IsEnglish(mode) && !WritePrivateProfileStringW(
          L"Input", L"LastChineseMode", std::to_wstring(NormalizeChinese(mode)).c_str(), path.c_str())) ||
      ReadIniModeRaw(L"Mode", -1) != mode ||
      (!IsEnglish(mode) && ReadIniModeRaw(L"LastChineseMode", -1) != NormalizeChinese(mode))) {
    restore_ini();
    return false;
  }

  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\GYInput", 0, nullptr, 0,
                      KEY_QUERY_VALUE | KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    // If HKCU cannot be writable, Read() deliberately treats the verified ini
    // as canonical. This covers old elevated installs with an inaccessible key.
    return !CanWriteRegistryState() && Read() == mode;
  }

  DWORD previous_registry_mode = 0;
  DWORD previous_registry_chinese = 0;
  DWORD value_size = sizeof(DWORD);
  DWORD type = 0;
  const bool had_registry_mode = RegQueryValueExW(key, L"InputMode", nullptr, &type,
      reinterpret_cast<BYTE*>(&previous_registry_mode), &value_size) == ERROR_SUCCESS && type == REG_DWORD;
  value_size = sizeof(DWORD);
  type = 0;
  const bool had_registry_chinese = RegQueryValueExW(key, L"LastChineseMode", nullptr, &type,
      reinterpret_cast<BYTE*>(&previous_registry_chinese), &value_size) == ERROR_SUCCESS && type == REG_DWORD;
  const auto restore_registry = [&] {
    if (had_registry_mode) {
      RegSetValueExW(key, L"InputMode", 0, REG_DWORD,
          reinterpret_cast<const BYTE*>(&previous_registry_mode), sizeof(previous_registry_mode));
    } else {
      RegDeleteValueW(key, L"InputMode");
    }
    if (had_registry_chinese) {
      RegSetValueExW(key, L"LastChineseMode", 0, REG_DWORD,
          reinterpret_cast<const BYTE*>(&previous_registry_chinese), sizeof(previous_registry_chinese));
    } else {
      RegDeleteValueW(key, L"LastChineseMode");
    }
  };

  const DWORD registry_mode = static_cast<DWORD>(mode);
  bool registry_ok = RegSetValueExW(key, L"InputMode", 0, REG_DWORD,
      reinterpret_cast<const BYTE*>(&registry_mode), sizeof(registry_mode)) == ERROR_SUCCESS;
  if (registry_ok && !IsEnglish(mode)) {
    const DWORD registry_chinese = static_cast<DWORD>(NormalizeChinese(mode));
    registry_ok = RegSetValueExW(key, L"LastChineseMode", 0, REG_DWORD,
        reinterpret_cast<const BYTE*>(&registry_chinese), sizeof(registry_chinese)) == ERROR_SUCCESS;
  }
  DWORD verified_mode = 0;
  value_size = sizeof(verified_mode);
  type = 0;
  registry_ok = registry_ok && RegQueryValueExW(key, L"InputMode", nullptr, &type,
      reinterpret_cast<BYTE*>(&verified_mode), &value_size) == ERROR_SUCCESS &&
      type == REG_DWORD && verified_mode == registry_mode;
  if (registry_ok && !IsEnglish(mode)) {
    DWORD verified_chinese = 0;
    value_size = sizeof(verified_chinese);
    type = 0;
    registry_ok = RegQueryValueExW(key, L"LastChineseMode", nullptr, &type,
        reinterpret_cast<BYTE*>(&verified_chinese), &value_size) == ERROR_SUCCESS &&
        type == REG_DWORD && verified_chinese == static_cast<DWORD>(NormalizeChinese(mode));
  }
  const bool verified = registry_ok && ReadIniModeRaw(L"Mode", -1) == mode && Read() == mode;
  if (!verified) {
    restore_registry();
    restore_ini();
    RegCloseKey(key);
    return false;
  }
  RegCloseKey(key);
  return true;
#endif
}

}  // namespace gy::input_mode
