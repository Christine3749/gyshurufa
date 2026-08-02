#include "SelectionCallback.h"

#include "HostProtocol.h"

#include <objbase.h>
#include <sddl.h>

#include <cwchar>
#include <iterator>
#include <limits>
#include <string>
#include <utility>

namespace {
constexpr wchar_t kCallbackClass[] = L"GyImeSelectionCallback";
constexpr UINT kSelectMessage = WM_APP + 73;

ATOM RegisterCallbackClass(HINSTANCE module) {
  static const ATOM atom = [module] {
    WNDCLASSEXW wc{sizeof(wc)};
    wc.lpfnWndProc = SelectionCallback::WindowProc;
    wc.hInstance = module;
    wc.lpszClassName = kCallbackClass;
    return RegisterClassExW(&wc);
  }();
  return atom;
}

std::wstring NewSessionId() {
  GUID guid{};
  if (FAILED(CoCreateGuid(&guid))) return {};
  wchar_t value[40]{};
  if (!StringFromGUID2(guid, value, static_cast<int>(std::size(value)))) return {};
  return value;
}

HANDLE CreateCallbackPipe(const std::wstring& endpoint) {
  // The GUID is a per-session capability token. The DACL adds a second guard:
  // only the interactive owner can connect to a callback that commits text.
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(L"D:P(A;;GA;;;OW)", SDDL_REVISION_1,
                                                              &descriptor, nullptr)) {
    return INVALID_HANDLE_VALUE;
  }
  SECURITY_ATTRIBUTES attributes{sizeof(attributes), descriptor, FALSE};
  HANDLE pipe = CreateNamedPipeW(endpoint.c_str(), PIPE_ACCESS_DUPLEX,
      PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
      1, gy::host::kMaxPayloadBytes, gy::host::kMaxPayloadBytes, 0, &attributes);
  LocalFree(descriptor);
  return pipe;
}
bool ParseIndex(const std::wstring& value, unsigned* index) {
  if (!index || value.empty()) return false;
  wchar_t* end = nullptr;
  const unsigned long parsed = wcstoul(value.c_str(), &end, 10);
  if (!end || *end != L'\0' || parsed > std::numeric_limits<unsigned>::max()) return false;
  *index = static_cast<unsigned>(parsed);
  return true;
}
}  // namespace

SelectionCallback::SelectionCallback(HINSTANCE module, std::function<void(unsigned)> on_select)
    : module_(module), on_select_(std::move(on_select)) {}

SelectionCallback::~SelectionCallback() { Stop(); }

bool SelectionCallback::Start() {
  Stop();
  const std::wstring session_id = NewSessionId();
  if (session_id.empty() || !RegisterCallbackClass(module_)) return false;
  endpoint_ = L"\\\\.\\pipe\\GYInput.Select." + session_id;
  hwnd_ = CreateWindowExW(0, kCallbackClass, L"", 0, 0, 0, 0, 0,
                          HWND_MESSAGE, nullptr, module_, this);
  if (!hwnd_) {
    endpoint_.clear();
    return false;
  }
  ready_event_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (!ready_event_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
    endpoint_.clear();
    return false;
  }
  running_.store(true);
  worker_ = std::thread(&SelectionCallback::Run, this);
  if (WaitForSingleObject(ready_event_, 1000) != WAIT_OBJECT_0) {
    Stop();
    return false;
  }
  return true;
}

void SelectionCallback::Stop() {
  if (!running_.exchange(false)) {
    if (hwnd_) { DestroyWindow(hwnd_); hwnd_ = nullptr; }
    if (ready_event_) { CloseHandle(ready_event_); ready_event_ = nullptr; }
    endpoint_.clear();
    return;
  }
  Wake();
  if (worker_.joinable()) worker_.join();
  if (hwnd_) { DestroyWindow(hwnd_); hwnd_ = nullptr; }
  if (ready_event_) { CloseHandle(ready_event_); ready_event_ = nullptr; }
  endpoint_.clear();
}
void SelectionCallback::Wake() {
  if (endpoint_.empty()) return;
  if (!WaitNamedPipeW(endpoint_.c_str(), 200)) return;
  HANDLE pipe = CreateFileW(endpoint_.c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (pipe != INVALID_HANDLE_VALUE) CloseHandle(pipe);
}

void SelectionCallback::Run() {
  while (running_.load()) {
    HANDLE pipe = CreateCallbackPipe(endpoint_);
    if (pipe == INVALID_HANDLE_VALUE) {
      if (ready_event_) SetEvent(ready_event_);
      return;
    }
    if (ready_event_) SetEvent(ready_event_);
    if (!running_.load()) { CloseHandle(pipe); return; }
    const BOOL connected = ConnectNamedPipe(pipe, nullptr) ? TRUE : GetLastError() == ERROR_PIPE_CONNECTED;
    if (connected) {
      gy::host::MessageType type{};
      std::wstring payload;
      std::wstring response = L"error";
      if (gy::host::ReadMessage(pipe, &type, &payload) && type == gy::host::MessageType::SelectCandidate) {
        unsigned index = 0;
        if (ParseIndex(payload, &index) && hwnd_ && PostMessageW(hwnd_, kSelectMessage, index, 0)) {
          response = L"ok";
        }
      }
      gy::host::WriteMessage(pipe, gy::host::MessageType::SelectCandidate, response);
      FlushFileBuffers(pipe);
    }
    DisconnectNamedPipe(pipe);
    CloseHandle(pipe);
  }
}

LRESULT CALLBACK SelectionCallback::WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<SelectionCallback*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = reinterpret_cast<SelectionCallback*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  if (self && message == kSelectMessage) {
    if (self->on_select_) self->on_select_(static_cast<unsigned>(wparam));
    return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}
