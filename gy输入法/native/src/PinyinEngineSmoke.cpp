#include <windows.h>

#include <iostream>
#include <string>

#include "InputMode.h"
#include "PinyinEngine.h"

namespace {
std::wstring g_local_app_data;

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
  if (!SetEnvironmentVariableW(L"LOCALAPPDATA", directory.c_str())) return false;
  g_local_app_data = directory;
  return true;
}

bool EnsureDirectory(const std::wstring& path) {
  return CreateDirectoryW(path.c_str(), nullptr) || GetLastError() == ERROR_ALREADY_EXISTS;
}

bool WriteAsciiFile(const std::wstring& path, const char* value) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  const DWORD expected = static_cast<DWORD>(lstrlenA(value));
  DWORD written = 0;
  const bool ok = WriteFile(file, value, expected, &written, nullptr) && written == expected;
  CloseHandle(file);
  return ok;
}

bool FileContainsAscii(const std::wstring& path, const char* needle) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  const DWORD size = GetFileSize(file, nullptr);
  if (size == INVALID_FILE_SIZE || size > 1024 * 1024) {
    CloseHandle(file);
    return false;
  }
  std::string content(size, '\0');
  DWORD read = 0;
  const bool ok = ReadFile(file, content.data(), size, &read, nullptr) && read == size;
  CloseHandle(file);
  return ok && content.find(needle) != std::string::npos;
}

bool SeedStaleGeneratedSchema() {
  const std::wstring gy_root = g_local_app_data + L"\\GYInput";
  const std::wstring rime_root = gy_root + L"\\rime";
  const std::wstring build_root = rime_root + L"\\build";
  if (!EnsureDirectory(gy_root) || !EnsureDirectory(rime_root) || !EnsureDirectory(build_root)) return false;
  return WriteAsciiFile(build_root + L"\\luna_pinyin.schema.yaml", "schema:\n  page_size: 5\n");
}

bool IsCjkIdeograph(wchar_t character) {
  return (character >= 0x3400 && character <= 0x4DBF) ||
         (character >= 0x4E00 && character <= 0x9FFF) ||
         (character >= 0xF900 && character <= 0xFAFF);
}

bool UsesOnlyHanCharacters(const std::vector<std::wstring>& candidates) {
  for (const std::wstring& candidate : candidates) {
    if (candidate.empty()) return false;
    for (const wchar_t character : candidate) {
      if (!IsCjkIdeograph(character)) return false;
    }
  }
  return true;
}

class ScopedInputMode final {
public:
  explicit ScopedInputMode(int mode) : previous_(gy::input_mode::Read()) {
    gy::input_mode::Write(mode);
  }

  ~ScopedInputMode() { gy::input_mode::Write(previous_); }

  ScopedInputMode(const ScopedInputMode&) = delete;
  ScopedInputMode& operator=(const ScopedInputMode&) = delete;

private:
  int previous_;
};
}  // namespace

int main() {
  if (!UseIsolatedLocalAppData()) {
    std::wcerr << L"Cannot create an isolated local data directory for the smoke test.\n";
    return 2;
  }
  // Upgrade regression: an old generated schema must be replaced, otherwise an
  // existing user stays on the legacy page_size and cannot open a full grid.
  // This smoke test validates Chinese candidate quality. The runtime mode is
  // shared across applications, so isolate the test from the user's current EN
  // or Traditional selection and restore it automatically on every exit path.
  const ScopedInputMode simplified_mode(gy::input_mode::kSimplified);
  if (!SeedStaleGeneratedSchema()) {
    std::wcerr << L"Cannot seed a stale generated Rime schema.\n";
    return 11;
  }
  PinyinEngine engine(ModuleDirectory());
  if (!engine.IsReady()) {
    std::wcerr << L"PinyinEngine did not initialize librime: " << engine.Diagnostic() << L"\n";
    return 1;
  }
  if (!FileContainsAscii(g_local_app_data + L"\\GYInput\\rime\\build\\luna_pinyin.schema.yaml", "page_size: 96")) {
    std::wcerr << L"The bundled Rime schema did not replace the stale generated cache.\n";
    return 12;
  }
  const auto candidates = engine.Lookup(L"nihao");
  for (const auto& candidate : candidates) std::wcout << candidate << L"\n";
  if (candidates.empty() || !UsesOnlyHanCharacters(candidates)) {
    std::wcerr << L"Candidate quality gate returned a non-Han value.\n";
    return 10;
  }
  const auto paging_candidates = engine.Lookup(L"wo");
  // Paging is unlocked: single-syllable queries fill the pool with one-
  // character candidates too. The pool ceiling (75) and the base quality gate
  // (CJK ideographs only) still apply to every page, and a common single-
  // syllable query must produce more than one page of candidates.
  if (paging_candidates.size() > 75) {
    std::wcerr << L"Candidate pool exceeded its 75-entry ceiling.\n";
    return 8;
  }
  if (paging_candidates.size() <= 25 || !UsesOnlyHanCharacters(paging_candidates)) {
    std::wcerr << L"Single-syllable paging stayed locked at 25 or admitted a non-Han entry.\n";
    return 8;
  }
  wchar_t local_app_data[MAX_PATH]{};
  if (!GetEnvironmentVariableW(L"LOCALAPPDATA", local_app_data, MAX_PATH)) return 3;
  const std::wstring settings = std::wstring(local_app_data) + L"\\GYInput\\settings.ini";
  HANDLE settings_file = CreateFileW(settings.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (settings_file == INVALID_HANDLE_VALUE) return 4;
  const wchar_t bom = 0xFEFF;
  DWORD written = 0;
  const bool unicode_ini = WriteFile(settings_file, &bom, sizeof(bom), &written, nullptr) && written == sizeof(bom);
  CloseHandle(settings_file);
  if (!unicode_ini || !WritePrivateProfileStringW(L"Phrases", L"dz", L"地址|电子邮箱", settings.c_str()) ||
      !WritePrivateProfileStringW(L"Phrases", L"dizhi ", L" 地址 ", settings.c_str()) ||
      !WritePrivateProfileStringW(L"Phrases", L"zg", L"中国", settings.c_str()) ||
      !WritePrivateProfileStringW(L"Input", L"Mode", L"1", settings.c_str())) return 4;
  // TSF instances use the shared registry mode at runtime. Make the smoke test
  // explicit and restore the user's mode automatically on every return path.
  const ScopedInputMode traditional_mode(gy::input_mode::kTraditional);
  const auto phrase_candidates = engine.Lookup(L"dz");
  if (phrase_candidates.size() < 2 || phrase_candidates[0] != L"地址" || phrase_candidates[1] != L"電子郵箱" ||
      !UsesOnlyHanCharacters(phrase_candidates)) {
    std::wcerr << L"Custom phrases bypassed the candidate quality gate.\n";
    return 5;
  }
  const auto trimmed_phrase_candidates = engine.Lookup(L"dizhi");
  if (trimmed_phrase_candidates.empty() || trimmed_phrase_candidates.front() != L"地址") {
    std::wcerr << L"A spaced custom phrase key was not normalized.\n";
    return 7;
  }

  const auto traditional_candidates = engine.Lookup(L"zg");
  if (traditional_candidates.empty() || traditional_candidates.front() != L"中國") {
    std::wcerr << L"Traditional mode did not normalize custom phrase output.\n";
    return 9;
  }
  const std::wstring learned_candidate = L"你好";
  engine.Learn(L"nihao", learned_candidate);
  const auto learned_candidates = engine.Lookup(L"nihao");
  if (learned_candidates.empty() || learned_candidates.front() != learned_candidate) {
    std::wcerr << L"Local learning did not promote the selected candidate.\n";
    return 6;
  }
  return 0;
}



