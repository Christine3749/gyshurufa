#include "HostProtocol.h"
#include "SelectionCallback.h"

#include <windows.h>

#include <atomic>
#include <iostream>
#include <string>
#include <thread>

namespace {
bool SendSelection(const std::wstring& endpoint, unsigned index) {
  if (!WaitNamedPipeW(endpoint.c_str(), 1000)) return false;
  HANDLE pipe = CreateFileW(endpoint.c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (pipe == INVALID_HANDLE_VALUE) return false;
  gy::host::MessageType response_type{};
  std::wstring response;
  const bool ok = gy::host::WriteMessage(pipe, gy::host::MessageType::SelectCandidate,
                                         std::to_wstring(index)) &&
                  gy::host::ReadMessage(pipe, &response_type, &response);
  CloseHandle(pipe);
  return ok && response_type == gy::host::MessageType::SelectCandidate && response == L"ok";
}
}

int wmain() {
  std::atomic_int selected{-1};
  SelectionCallback callback(GetModuleHandleW(nullptr), [&selected](unsigned index) {
    selected.store(static_cast<int>(index));
    return true;
  });
  if (!callback.Start()) {
    std::wcerr << L"Selection callback did not start.\n";
    return 1;
  }
  std::atomic_bool request_finished{false};
  std::atomic_bool request_ok{false};
  std::thread sender([&] {
    request_ok.store(SendSelection(callback.Endpoint(), 3));
    request_finished.store(true);
  });
  const ULONGLONG deadline = GetTickCount64() + 1000;
  MSG message{};
  while ((!request_finished.load() || selected.load() < 0) && GetTickCount64() < deadline) {
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    Sleep(1);
  }
  sender.join();
  callback.Stop();
  if (!request_ok.load() || selected.load() != 3) {
    std::wcerr << L"Selection callback did not return to its owner thread.\n";
    return 2;
  }
  std::wcout << L"Selection callback smoke passed.\n";
  return 0;
}