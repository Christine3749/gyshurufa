#include <windows.h>

#include <iostream>
#include <string>

#include "PinyinEngine.h"

namespace {
std::wstring ModuleDirectory() {
  wchar_t path[MAX_PATH]{};
  const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (!length || length == MAX_PATH) return {};
  std::wstring directory(path, length);
  directory.resize(directory.find_last_of(L"\\/"));
  return directory;
}

bool UseIsolatedLocalAppData() {
  wchar_t temp[MAX_PATH]{};
  const DWORD length = GetTempPathW(MAX_PATH, temp);
  if (!length || length >= MAX_PATH) return false;
  const std::wstring directory = std::wstring(temp) + L"GYInput-PinyinSmoke-" +
      std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64());
  if (!CreateDirectoryW(directory.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) return false;
  return SetEnvironmentVariableW(L"LOCALAPPDATA", directory.c_str()) != FALSE;
}
}  // namespace

int main() {
  if (!UseIsolatedLocalAppData()) {
    std::wcerr << L"Cannot create an isolated local data directory for the smoke test.\n";
    return 2;
  }
  PinyinEngine engine(ModuleDirectory());
  if (!engine.IsReady()) {
    std::wcerr << L"PinyinEngine did not initialize librime: " << engine.Diagnostic() << L"\n";
    return 1;
  }
  const auto candidates = engine.Lookup(L"nihao");
  for (const auto& candidate : candidates) std::wcout << candidate << L"\n";
  if (candidates.empty()) return 1;
  const auto paging_candidates = engine.Lookup(L"wo");
  if (paging_candidates.size() <= 5) {
    std::wcerr << L"The engine did not return a second candidate page.\n";
    return 8;
  }

  wchar_t local_app_data[MAX_PATH]{};
  if (!GetEnvironmentVariableW(L"LOCALAPPDATA", local_app_data, MAX_PATH)) return 3;
  const std::wstring settings = std::wstring(local_app_data) + L"\\GYInput\\settings.ini";
  HANDLE settings_file = CreateFileW(settings.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (settings_file == INVALID_HANDLE_VALUE) return 4;
  const wchar_t bom = 0xFEFF;
  DWORD written = 0;
  const bool unicode_ini = WriteFile(settings_file, &bom, sizeof(bom), &written, nullptr) && written == sizeof(bom);
  CloseHandle(settings_file);
  if (!unicode_ini || !WritePrivateProfileStringW(L"Phrases", L"dz", L"地址|电子邮箱", settings.c_str()) ||
      !WritePrivateProfileStringW(L"Phrases", L"dizhi ", L" 地址 ", settings.c_str())) return 4;
  const auto phrase_candidates = engine.Lookup(L"dz");
  if (phrase_candidates.size() < 2 || phrase_candidates[0] != L"地址" || phrase_candidates[1] != L"电子邮箱") {
    std::wcerr << L"Multiple custom phrases did not rank first.\n";
    return 5;
  }
  const auto trimmed_phrase_candidates = engine.Lookup(L"dizhi");
  if (trimmed_phrase_candidates.empty() || trimmed_phrase_candidates.front() != L"地址") {
    std::wcerr << L"A spaced custom phrase key was not normalized.\n";
    return 7;
  }

  const std::wstring learned_candidate = candidates.back();
  engine.Learn(L"nihao", learned_candidate);
  const auto learned_candidates = engine.Lookup(L"nihao");
  if (learned_candidates.empty() || learned_candidates.front() != learned_candidate) {
    std::wcerr << L"Local learning did not promote the selected candidate.\n";
    return 6;
  }
  return 0;
}


