#pragma once

#include <windows.h>

#include <atomic>
#include <functional>
#include <string>
#include <thread>

// One callback endpoint per TSF service instance. Host UI returns only a
// candidate index; the callback window runs on the original TSF thread and
// therefore remains the only component that can request an edit session.
class SelectionCallback {
public:
  SelectionCallback(HINSTANCE module, std::function<void(unsigned)> on_select);
  ~SelectionCallback();
  SelectionCallback(const SelectionCallback&) = delete;
  SelectionCallback& operator=(const SelectionCallback&) = delete;

  bool Start();
  void Stop();
  [[nodiscard]] const std::wstring& Endpoint() const { return endpoint_; }
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

private:
  void Run();
  void Wake();

  HINSTANCE module_ = nullptr;
  HWND hwnd_ = nullptr;
  HANDLE ready_event_ = nullptr;
  std::wstring endpoint_;
  std::function<void(unsigned)> on_select_;
  std::atomic_bool running_{false};
  std::thread worker_;
};