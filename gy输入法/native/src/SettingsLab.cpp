#include "SettingsWindow.h"

#include <windows.h>

#include <string>

namespace {
constexpr wchar_t kSettingsClass[] = L"GyImeSettingsWindow";

std::wstring PreviewLocalAppData() {
  wchar_t temporary[MAX_PATH]{};
  const DWORD length = GetTempPathW(MAX_PATH, temporary);
  if (length == 0 || length >= MAX_PATH) return {};
  return std::wstring(temporary, length) + L"GY-SettingsLab-" +
         std::to_wstring(GetCurrentProcessId());
}

int PreviewScalePreference() {
  wchar_t value[8]{};
  const DWORD length = GetEnvironmentVariableW(
      L"GYINPUT_SETTINGS_LAB_SCALE", value, static_cast<DWORD>(std::size(value)));
  if (length > 0 && length < std::size(value)) {
    if (value[0] == L'9' && value[1] == L'5') return 95;
    if (value[0] == L'1') return 100;
  }
  return 0;
}
}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  const std::wstring preview_local_app_data = PreviewLocalAppData();
  if (preview_local_app_data.empty() ||
      (!CreateDirectoryW(preview_local_app_data.c_str(), nullptr) &&
       GetLastError() != ERROR_ALREADY_EXISTS) ||
      !SetEnvironmentVariableW(L"LOCALAPPDATA", preview_local_app_data.c_str())) {
    return 10;
  }
  const std::wstring settings_directory = preview_local_app_data + L"\\GYInput";
  CreateDirectoryW(settings_directory.c_str(), nullptr);
  WritePrivateProfileStringW(L"Appearance", L"CandidateScale",
                             std::to_wstring(PreviewScalePreference()).c_str(),
                             (settings_directory + L"\\settings.ini").c_str());

  SettingsWindow settings;
  const RECT anchor{120, 1040, 121, 1041};
  settings.Show(anchor);
  if (!FindWindowW(kSettingsClass, nullptr)) return 11;

  SetTimer(nullptr, 1, 100, nullptr);
  MSG message{};
  while (GetMessageW(&message, nullptr, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
    if (!FindWindowW(kSettingsClass, nullptr)) break;
  }
  return 0;
}
