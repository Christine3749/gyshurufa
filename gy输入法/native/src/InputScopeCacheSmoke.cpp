#include "InputScopeCache.h"

#include <windows.h>

#include <iostream>
#include <string>

int wmain() {
  const std::wstring name = L"Local\\GYInput.InputScopeCache.test." +
      std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64());
  if (!SetEnvironmentVariableW(L"GYINPUT_SCOPE_CACHE", name.c_str())) return 1;
  gy::input_scope_cache::Writer writer;
  gy::input_scope_cache::Reader reader;
  reader.Attach();

  const HWND foreground = GetForegroundWindow();
  DWORD process_id = 0;
  if (!foreground || !GetWindowThreadProcessId(foreground, &process_id)) return 2;
  writer.Publish(foreground, process_id, true, true);
  bool direct = false;
  bool sensitive = false;
  if (!reader.ReadForCurrentForeground(&direct, &sensitive) || !direct || !sensitive) {
    std::wcerr << L"Current foreground snapshot did not round-trip.\n";
    return 3;
  }
  // A different field/window inside the same application must not inherit a
  // short-lived direct-input decision from the previous focused field.
  writer.Publish(reinterpret_cast<HWND>(static_cast<ULONG_PTR>(1)), process_id, true, true);
  direct = false;
  sensitive = false;
  if (reader.ReadForCurrentForeground(&direct, &sensitive)) {
    std::wcerr << L"A different-window snapshot leaked into the current focus.\n";
    return 4;
  }
  // A record for another process must never make this focused window direct.
  writer.Publish(foreground, process_id + 1, true, true);
  direct = false;
  sensitive = false;
  if (reader.ReadForCurrentForeground(&direct, &sensitive)) {
    std::wcerr << L"A different-process snapshot leaked into the current focus.\n";
    return 5;
  }
  return 0;
}
