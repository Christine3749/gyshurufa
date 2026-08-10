#include "HostedPinyinEngine.h"
#include "HostProtocol.h"
#include "NativeTestInputMode.h"

#include <windows.h>

#include <algorithm>
#include <iostream>
#include <string>
#include <vector>

#ifndef GY_HOST_VERSION
#define GY_HOST_VERSION "dev"
#endif
#define GY_SMOKE_WIDEN_INNER(value) L##value
#define GY_SMOKE_WIDEN(value) GY_SMOKE_WIDEN_INNER(value)

namespace {
std::wstring ModuleDirectory() {
  wchar_t path[MAX_PATH]{};
  const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (!length || length >= MAX_PATH) return {};
  std::wstring result(path, length);
  const size_t slash = result.find_last_of(L"\\/");
  return slash == std::wstring::npos ? std::wstring{} : result.substr(0, slash);
}

bool IsHanOnly(const std::vector<std::wstring>& candidates) {
  const auto is_han = [](wchar_t character) {
    return (character >= 0x3400 && character <= 0x4DBF) ||
        (character >= 0x4E00 && character <= 0x9FFF) ||
        (character >= 0xF900 && character <= 0xFAFF);
  };
  return !candidates.empty() && std::all_of(candidates.begin(), candidates.end(),
      [&is_han](const std::wstring& candidate) {
        return !candidate.empty() &&
            std::all_of(candidate.begin(), candidate.end(), is_han);
      });
}

bool PrepareEnvironment(const std::wstring& directory) {
  wchar_t temp[MAX_PATH]{};
  const DWORD length = GetTempPathW(MAX_PATH, temp);
  if (!length || length >= MAX_PATH) return false;
  const std::wstring suffix = std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64());
  const std::wstring local = std::wstring(temp) + L"GYInput-HostedSmoke-" + suffix;
  const std::wstring pipe = L"\\\\.\\pipe\\GYInput.Host.test." + suffix;
  const std::wstring host = directory + L"\\GyImeHost.exe";
  return CreateDirectoryW(local.c_str(), nullptr) != FALSE &&
      SetEnvironmentVariableW(L"LOCALAPPDATA", local.c_str()) != FALSE &&
      SetEnvironmentVariableW(L"GYINPUT_HOST_PIPE", pipe.c_str()) != FALSE &&
      SetEnvironmentVariableW(L"GYINPUT_HOST_PATH", host.c_str()) != FALSE &&
      SetEnvironmentVariableW(L"GYINPUT_HOST_VERSION", GY_SMOKE_WIDEN(GY_HOST_VERSION)) != FALSE &&
      SetEnvironmentVariableW(L"GYINPUT_HOST_NO_TRAY", L"1") != FALSE;
}

bool Send(gy::host::MessageType type, std::wstring* response = nullptr) {
  HANDLE pipe = INVALID_HANDLE_VALUE;
  const ULONGLONG deadline = GetTickCount64() + 4000;
  do {
    if (WaitNamedPipeW(gy::host::HostPipeName().c_str(), 20)) {
      pipe = CreateFileW(gy::host::HostPipeName().c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                         nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
      if (pipe != INVALID_HANDLE_VALUE) break;
    }
    Sleep(10);
  } while (GetTickCount64() < deadline);
  if (pipe == INVALID_HANDLE_VALUE) return false;
  gy::host::MessageType result_type{};
  std::wstring payload;
  const bool ok = gy::host::WriteMessage(pipe, type, L"") &&
      gy::host::ReadMessage(pipe, &result_type, &payload) && result_type == type;
  CloseHandle(pipe);
  if (ok && response) *response = std::move(payload);
  return ok;
}
}  // namespace

int wmain() {
  const std::wstring directory = ModuleDirectory();
  if (directory.empty() || !PrepareEnvironment(directory)) {
    std::wcerr << L"Cannot prepare isolated hosted-engine test.\n";
    return 1;
  }
  const gy::test::ScopedInputMode simplified_mode(gy::input_mode::kSimplified);
  HostedPinyinEngine engine(directory);
  const auto first = engine.Lookup(L"nihao");
  if (first.empty()) {
    std::wcerr << L"The DLL-side Host bootstrap did not return candidates: " << engine.Diagnostic() << L"\n";
    return 2;
  }
  // This crosses the same DLL -> Host IPC boundary as the user-facing IME.
  // A local-engine-only test is insufficient: a stale Host must never publish
  // a sparse 3-column panel as though the 5x5 release rule had passed.
  const auto expanded = engine.Lookup(L"wo");
  if (expanded.size() < 20 || !IsHanOnly(expanded)) {
    std::wcerr << L"Hosted candidate pool cannot support a 5x5 grid: "
               << expanded.size() << L" qualified candidates.\n";
    return 5;
  }
  const auto remaining = engine.RemainingPinyin(L"lihouyi", L"李");
  if (remaining != L"houyi") {
    std::wcerr << L"Prefix candidate resolution swallowed or mis-sized the remaining pinyin: " << remaining << L"\n";
    Send(gy::host::MessageType::Shutdown);
    return 6;
  }
  const auto chained_remaining = engine.RemainingPinyin(L"houyi", L"厚");
  if (chained_remaining != L"yi") {
    std::wcerr << L"Chained prefix candidate resolution swallowed or mis-sized the remaining pinyin: "
               << chained_remaining << L"\n";
    Send(gy::host::MessageType::Shutdown);
    return 7;
  }
  if (!Send(gy::host::MessageType::Shutdown)) {
    std::wcerr << L"Cannot request a private Host shutdown.\n";
    return 3;
  }
  Sleep(80);
  const auto recovered = engine.Lookup(L"nihao");
  std::wstring version;
  const bool version_ok = Send(gy::host::MessageType::Status, &version) && version == GY_SMOKE_WIDEN(GY_HOST_VERSION);
  Send(gy::host::MessageType::Shutdown);
  if (recovered.empty() || !version_ok) {
    std::wcerr << L"The DLL-side Host recovery failed: " << engine.Diagnostic() << L"\n";
    return 4;
  }
  return 0;
}
