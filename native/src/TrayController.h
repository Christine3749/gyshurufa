#pragma once

#include <windows.h>
#include <functional>

#include <string>

// The Windows taskbar owns language switching. This small Host-owned tray
// entry gives GY a persistent, separate settings entry without putting brand
// or configuration controls in the candidate strip.
class TrayController {
public:
  TrayController(std::wstring host_directory, std::function<void()> open_settings);
  ~TrayController();
  TrayController(const TrayController&) = delete;
  TrayController& operator=(const TrayController&) = delete;

  bool Start();
  void Stop();
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  void ShowMenu();
  void OpenSettings() const;

  std::wstring host_directory_;
  std::function<void()> open_settings_;
  HWND hwnd_ = nullptr;
  HICON icon_ = nullptr;
  bool icon_added_ = false;
};