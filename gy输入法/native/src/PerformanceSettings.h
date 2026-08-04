#pragma once

#include <windows.h>

#include <string>

// Warm start ("热启动") keeps the engine hot: the DLL caches host liveness for
// a short TTL and the Host pre-accepts a pool of pipe instances so keystrokes
// attach instantly. Measured resident cost is near zero (idle waits, a few
// pipe handles), but low-spec machines can turn it off from the settings
// panel; every consumer re-reads this on its own refresh cadence.
namespace gy::performance {
inline std::wstring SettingsPath() {
  wchar_t root[MAX_PATH]{};
  if (!GetEnvironmentVariableW(L"LOCALAPPDATA", root, MAX_PATH)) return {};
  return std::wstring(root) + L"\\GYInput\\settings.ini";
}

inline bool WarmStartEnabled() {
  const std::wstring path = SettingsPath();
  if (path.empty()) return true;
  return GetPrivateProfileIntW(L"Performance", L"WarmStart", 1, path.c_str()) != 0;
}
}  // namespace gy::performance
