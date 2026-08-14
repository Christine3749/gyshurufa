#include "HostedPinyinEngine.h"

#include <windows.h>

#include <chrono>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

namespace {

#define GY_WIDEN_VERSION_INNER(value) L##value
#define GY_WIDEN_VERSION(value) GY_WIDEN_VERSION_INNER(value)

struct StalledPipe {
  explicit StalledPipe(std::wstring name) : name_(std::move(name)) {}

  bool Start() {
    pipe_ = CreateNamedPipeW(name_.c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
                             PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1,
                             4096, 4096, 0, nullptr);
    if (pipe_ == INVALID_HANDLE_VALUE) return false;
    worker_ = std::thread([this] {
      OVERLAPPED connect{};
      connect.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
      if (!connect.hEvent) return;
      const BOOL connected = ConnectNamedPipe(pipe_, &connect);
      bool accepted = connected != FALSE;
      if (!accepted && GetLastError() == ERROR_PIPE_CONNECTED) {
        accepted = true;
      } else if (!accepted && GetLastError() == ERROR_IO_PENDING) {
        accepted = WaitForSingleObject(connect.hEvent, 1000) == WAIT_OBJECT_0;
      }
      if (accepted) {
        // Intentionally consume neither request nor response.  The client
        // must cancel its pending read by its own deadline.
        Sleep(120);
        DisconnectNamedPipe(pipe_);
      }
      CloseHandle(connect.hEvent);
    });
    return true;
  }

  ~StalledPipe() {
    if (worker_.joinable()) worker_.join();
    if (pipe_ != INVALID_HANDLE_VALUE) CloseHandle(pipe_);
  }

 private:
  std::wstring name_;
  HANDLE pipe_ = INVALID_HANDLE_VALUE;
  std::thread worker_;
};

bool PrepareEnvironment(std::wstring* pipe_name) {
  if (!pipe_name) return false;
  *pipe_name = L"\\\\.\\pipe\\GYInput.Host.test.deadline-" +
      std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64());
  return SetEnvironmentVariableW(L"GYINPUT_HOST_PIPE", pipe_name->c_str()) != FALSE &&
      SetEnvironmentVariableW(L"GYINPUT_HOST_PATH", L"C:\\nonexistent\\GyImeHost.exe") != FALSE &&
      SetEnvironmentVariableW(L"GYINPUT_HOST_VERSION", GY_WIDEN_VERSION(GY_HOST_VERSION)) != FALSE;
}

}  // namespace

#undef GY_WIDEN_VERSION
#undef GY_WIDEN_VERSION_INNER

int wmain() {
  std::wstring pipe_name;
  if (!PrepareEnvironment(&pipe_name)) {
    std::wcerr << L"Cannot prepare isolated stalled-pipe test.\n";
    return 1;
  }
  StalledPipe stalled(pipe_name);
  if (!stalled.Start()) {
    std::wcerr << L"Cannot create isolated stalled pipe.\n";
    return 2;
  }

  HostedPinyinEngine engine(L"C:\\nonexistent");
  const auto started = std::chrono::steady_clock::now();
  const std::vector<std::wstring> candidates = engine.Lookup(L"nihao", 0, 1);
  const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::steady_clock::now() - started).count();

  // 35ms is the implementation budget.  Leave scheduling headroom while
  // still proving that a non-responsive Host cannot become a visible freeze.
  if (!candidates.empty() || elapsed > 100) {
    std::wcerr << L"A stalled Host escaped the input deadline: " << elapsed
               << L"ms, candidates=" << candidates.size() << L"\n";
    return 3;
  }
  return 0;
}
