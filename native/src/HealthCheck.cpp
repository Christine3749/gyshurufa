#include <windows.h>

#include <iostream>
#include <string>

#include "PinyinEngine.h"
#include "NativeTestInputMode.h"

namespace {
std::wstring ModuleDirectory() {
  wchar_t path[MAX_PATH]{};
  const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (!length || length >= MAX_PATH) return {};
  std::wstring directory(path, length);
  const size_t slash = directory.find_last_of(L"\\/");
  return slash == std::wstring::npos ? std::wstring{} : directory.substr(0, slash);
}

bool UseIsolatedLocalAppData() {
  wchar_t temp[MAX_PATH]{};
  const DWORD length = GetTempPathW(MAX_PATH, temp);
  if (!length || length >= MAX_PATH) return false;
  const std::wstring directory = std::wstring(temp) + L"GYInput-Health-" +
      std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64());
  if (!CreateDirectoryW(directory.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) return false;
  return SetEnvironmentVariableW(L"LOCALAPPDATA", directory.c_str()) != FALSE;
}
}

int main() {
  if (!UseIsolatedLocalAppData()) return 9;
  const gy::test::ScopedInputMode simplified_mode(gy::input_mode::kSimplified);
  PinyinEngine engine(ModuleDirectory());
  if (!engine.IsReady()) { std::wcerr << engine.Diagnostic() << L"\n"; return 10; }
  return engine.Lookup(L"nihao").empty() ? 11 : 0;
}
