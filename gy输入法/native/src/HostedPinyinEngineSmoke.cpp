#include "HostedPinyinEngine.h"
#include "HostProtocol.h"

#include <windows.h>

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
  HostedPinyinEngine engine(directory);
  const auto first = engine.Lookup(L"nihao");
  if (first.empty()) {
    std::wcerr << L"The DLL-side Host bootstrap did not return candidates: " << engine.Diagnostic() << L"\n";
    return 2;
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