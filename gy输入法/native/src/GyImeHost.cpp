#include "CandidateWindow.h"
#include "HostProtocol.h"
#include "PinyinEngine.h"
#include "SettingsWindow.h"
#include "TrayController.h"

#include <windows.h>
#include <sddl.h>

#include <atomic>
#include <string>
#include <thread>
#include <iterator>

#ifndef GY_HOST_VERSION
#define GY_HOST_VERSION "dev"
#endif
#define GY_WIDEN_INNER(value) L##value
#define GY_WIDEN(value) GY_WIDEN_INNER(value)

namespace {
constexpr UINT kUiCommandMessage = WM_APP + 41;
constexpr unsigned kCandidatesPerPage = 5;

#ifdef GY_TESTING
void DebugStep(const wchar_t* step) {
  wchar_t temp[MAX_PATH]{};
  if (!GetTempPathW(MAX_PATH, temp)) return;
  const std::wstring path = std::wstring(temp) + L"gyhost-debug.log";
  HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ, nullptr, OPEN_ALWAYS,
                            FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  WriteFile(file, step, static_cast<DWORD>(wcslen(step) * sizeof(wchar_t)), &written, nullptr);
  WriteFile(file, L"\n", sizeof(wchar_t), &written, nullptr);
  CloseHandle(file);
}
#else
#define DebugStep(step) ((void)0)
#endif

enum class UiCommandKind { ShowCandidates, HideCandidates, ShowMode };

struct UiCommand {
  UiCommandKind kind = UiCommandKind::HideCandidates;
  gy::host::CandidateUiState state{};
};

std::wstring HostInstanceMutexName() {
  const std::wstring pipe = gy::host::HostPipeName();
  if (pipe == gy::host::kPipeName) return L"Local\\GYInput.Host.v1";
  // The only accepted override uses the private test pipe prefix. Give that
  // isolated Host its own mutex so it can never collide with the user Host.
  return L"Local\\GYInput.Host.test." + pipe.substr(pipe.find_last_of(L".") + 1);
}
std::wstring ModuleDirectory() {
  wchar_t path[MAX_PATH]{};
  const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) return L".";
  std::wstring directory(path, length);
  const size_t slash = directory.find_last_of(L"\\/");
  return slash == std::wstring::npos ? L"." : directory.substr(0, slash);
}

constexpr DWORD kPipeInstanceCount = 8;

SECURITY_ATTRIBUTES* PipeSecurityAttributes() {
  // Cached for the process lifetime. Parsing the SDDL used to happen on every
  // single client connection and was part of the ~15ms accept-recycle cost.
  static SECURITY_ATTRIBUTES* cached = [] {
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(L"D:P(A;;GA;;;OW)", SDDL_REVISION_1,
                                                              &descriptor, nullptr)) {
      return static_cast<SECURITY_ATTRIBUTES*>(nullptr);
    }
    return new SECURITY_ATTRIBUTES{sizeof(SECURITY_ATTRIBUTES), descriptor, FALSE};
  }();
  return cached;
}

HANDLE CreateServerPipe() {
  // The IME Host can carry active composition data. Limit this IPC endpoint to
  // the owner of the Host process instead of accepting connections from other
  // local accounts. Remote clients are separately rejected by the pipe mode.
  SECURITY_ATTRIBUTES* attributes = PipeSecurityAttributes();
  if (!attributes) return INVALID_HANDLE_VALUE;
  return CreateNamedPipeW(gy::host::HostPipeName().c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
      PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
      kPipeInstanceCount, gy::host::kMaxPayloadBytes, gy::host::kMaxPayloadBytes, 0, attributes);
}

bool IsSelectionEndpoint(const std::wstring& endpoint) {
  constexpr wchar_t prefix[] = L"\\\\.\\pipe\\GYInput.Select.";
  constexpr size_t guid_length = 38;  // {xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}
  return endpoint.size() == (std::size(prefix) - 1 + guid_length) &&
         endpoint.rfind(prefix, 0) == 0;
}
bool SendCandidateSelection(const std::wstring& callback_pipe, unsigned index) {
  // Host never injects a keyboard event. The target TSF DLL owns this private,
  // per-session endpoint and commits on its own editor thread.
  if (!IsSelectionEndpoint(callback_pipe) || !WaitNamedPipeW(callback_pipe.c_str(), 150)) return false;
  HANDLE pipe = CreateFileW(callback_pipe.c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (pipe == INVALID_HANDLE_VALUE) return false;
  gy::host::MessageType response_type{};
  std::wstring response;
  const bool sent = gy::host::WriteMessage(pipe, gy::host::MessageType::SelectCandidate,
                                           std::to_wstring(index)) &&
                    gy::host::ReadMessage(pipe, &response_type, &response);
  CloseHandle(pipe);
  return sent && response_type == gy::host::MessageType::SelectCandidate && response == L"ok";
}

class HostUi final {
public:
  HostUi() : candidates_([this](unsigned index) { return SendCandidateSelection(callback_pipe_, index); }, [this](const RECT& anchor) { settings_.Show(anchor); }) {}

  void Apply(UiCommand* command) {
    if (!command) return;
    switch (command->kind) {
      case UiCommandKind::ShowCandidates:
        callback_pipe_ = command->state.callback_pipe;
        // Preedit is already rendered by the focused app through TSF. The Host
        // deliberately draws only the horizontal candidate strip below it.
        candidates_.Show(command->state.caret, L"", command->state.candidates,
                         command->state.selected, command->state.page_start, static_cast<int>(command->state.input_mode),
                         command->state.expanded);
        break;
      case UiCommandKind::HideCandidates:
        callback_pipe_.clear();
        candidates_.Hide();
        break;
      case UiCommandKind::ShowMode:
        candidates_.ShowMode(command->state.caret, static_cast<int>(command->state.input_mode));
        break;
    }
  }

  void ShowSettings() {
    POINT point{};
    GetCursorPos(&point);
    const RECT anchor{point.x, point.y, point.x + 1, point.y + 1};
    settings_.Show(anchor);
  }

private:
  SettingsWindow settings_;
  std::wstring callback_pipe_;
  CandidateWindow candidates_;
};
bool QueueUiCommand(DWORD ui_thread_id, UiCommand* command) {
  if (!command) return false;
  if (PostThreadMessageW(ui_thread_id, kUiCommandMessage,
                         reinterpret_cast<WPARAM>(command), 0)) return true;
  delete command;
  return false;
}

std::wstring DispatchRequest(gy::host::MessageType type, const std::wstring& request,
                             PinyinEngine* engine, DWORD ui_thread_id, std::atomic_bool* running) {
  std::wstring response = L"ok";
  if (type == gy::host::MessageType::Lookup) {
    response = gy::host::EncodeCandidates(engine->Lookup(request));
  } else if (type == gy::host::MessageType::Status) {
    response = GY_WIDEN(GY_HOST_VERSION);
  } else if (type == gy::host::MessageType::ShowCandidates) {
    auto* command = new UiCommand{};
    command->kind = UiCommandKind::ShowCandidates;
    if (!gy::host::DecodeCandidateUi(request, &command->state) || !QueueUiCommand(ui_thread_id, command)) {
      response = L"error";
    }
  } else if (type == gy::host::MessageType::HideCandidates) {
    auto* command = new UiCommand{};
    command->kind = UiCommandKind::HideCandidates;
    if (!QueueUiCommand(ui_thread_id, command)) response = L"error";
  } else if (type == gy::host::MessageType::ShowMode) {
    auto* command = new UiCommand{};
    command->kind = UiCommandKind::ShowMode;
    if (!gy::host::DecodeCandidateUi(request, &command->state) || !QueueUiCommand(ui_thread_id, command)) {
      response = L"error";
    }
  } else if (type == gy::host::MessageType::LearnCandidate) {
    std::wstring pinyin;
    std::wstring candidate;
    if (!gy::host::DecodeLearningEvent(request, &pinyin, &candidate)) {
      response = L"error";
    } else {
      engine->Learn(pinyin, candidate);
    }
  } else if (type == gy::host::MessageType::Shutdown) {
    running->store(false);
    PostThreadMessageW(ui_thread_id, WM_QUIT, 0, 0);
  } else {
    response = L"unsupported";
  }
  return response;
}

struct PipeListener {
  HANDLE pipe = INVALID_HANDLE_VALUE;
  OVERLAPPED overlapped{};
};

bool BeginAccept(PipeListener* listener) {
  listener->pipe = CreateServerPipe();
  if (listener->pipe == INVALID_HANDLE_VALUE) return false;
  ResetEvent(listener->overlapped.hEvent);
  const BOOL connected = ConnectNamedPipe(listener->pipe, &listener->overlapped);
  if (connected || GetLastError() == ERROR_PIPE_CONNECTED) {
    SetEvent(listener->overlapped.hEvent);  // a client was already waiting
    return true;
  }
  return GetLastError() == ERROR_IO_PENDING;
}

void ServeRequests(PinyinEngine* engine, std::atomic_bool* running, DWORD ui_thread_id,
                   HANDLE stop_event) {
  if (!engine || !running || !stop_event) return;
  // A pool of pre-accepted instances lets back-to-back keystroke connections
  // attach instantly. The old single-instance server recycled its one pipe
  // after every request, so each new connection waited ~15ms in WaitNamedPipe;
  // bursts (4 connections per keystroke) and multiple apps amplified that.
  std::vector<PipeListener> listeners(kPipeInstanceCount);
  std::vector<HANDLE> wait_handles;
  wait_handles.push_back(stop_event);
  for (auto& listener : listeners) {
    listener.overlapped.hEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!listener.overlapped.hEvent || !BeginAccept(&listener)) break;
    wait_handles.push_back(listener.overlapped.hEvent);
  }
  // Keep only the listeners that actually started; index alignment with
  // wait_handles depends on it. Events from failed starts are closed here.
  for (size_t i = wait_handles.size() - 1; i < listeners.size(); ++i) {
    if (listeners[i].overlapped.hEvent) CloseHandle(listeners[i].overlapped.hEvent);
    if (listeners[i].pipe != INVALID_HANDLE_VALUE) CloseHandle(listeners[i].pipe);
  }
  listeners.resize(wait_handles.size() - 1);
  if (listeners.empty()) return;
  DebugStep((L"step: listeners ready count=" + std::to_wstring(listeners.size())).c_str());

  // Server pipes are opened with FILE_FLAG_OVERLAPPED, so message I/O must go
  // through the overlapped protocol helpers with a manual-reset event.
  OVERLAPPED io{};
  io.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (!io.hEvent) return;

  while (running->load()) {
    const DWORD wait = WaitForMultipleObjects(static_cast<DWORD>(wait_handles.size()),
                                              wait_handles.data(), FALSE, INFINITE);
    if (wait == WAIT_OBJECT_0 || wait == WAIT_FAILED) break;
    const size_t index = wait - WAIT_OBJECT_0 - 1;
    if (index >= listeners.size()) break;
    PipeListener& listener = listeners[index];
    DWORD ignored = 0;
    GetOverlappedResult(listener.pipe, &listener.overlapped, &ignored, FALSE);

    gy::host::MessageType type{};
    std::wstring request;
    if (gy::host::ReadMessageOverlapped(listener.pipe, &io, &type, &request)) {
      const std::wstring response = DispatchRequest(type, request, engine, ui_thread_id, running);
      gy::host::WriteMessageOverlapped(listener.pipe, &io, type, response);
      FlushFileBuffers(listener.pipe);
    }
    DisconnectNamedPipe(listener.pipe);
    CloseHandle(listener.pipe);
    listener.pipe = INVALID_HANDLE_VALUE;
    BeginAccept(&listener);  // immediately offer a fresh pending accept
  }

  CloseHandle(io.hEvent);
  for (auto& listener : listeners) {
    if (listener.pipe != INVALID_HANDLE_VALUE) {
      CancelIoEx(listener.pipe, &listener.overlapped);
      DisconnectNamedPipe(listener.pipe);
      CloseHandle(listener.pipe);
    }
    if (listener.overlapped.hEvent) CloseHandle(listener.overlapped.hEvent);
  }
}
}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  DebugStep(L"step: process start");
#ifdef GY_TESTING
  wchar_t envbuf[256]{};
  const DWORD envlen = GetEnvironmentVariableW(L"GYINPUT_HOST_PIPE", envbuf, 256);
  DebugStep((L"step: env pipe len=" + std::to_wstring(envlen) + L" val=" + envbuf).c_str());
  DebugStep((L"step: resolved pipe=" + gy::host::HostPipeName()).c_str());
#endif
  // Render at the active monitor DPI. Otherwise Windows virtualizes this GDI
  // surface at 96 DPI and 175% scaling makes Chinese glyphs look soft.
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  const std::wstring mutex_name = HostInstanceMutexName();
  DebugStep((L"step: mutex=" + mutex_name).c_str());
  HANDLE single_instance = CreateMutexW(nullptr, FALSE, mutex_name.c_str());
  if (!single_instance) { DebugStep(L"exit: mutex null"); return 2; }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    DebugStep(L"exit: mutex already exists");
    CloseHandle(single_instance);
    return 0;
  }

  // Create the message queue before accepting IPC so queued UI commands always.
  // have an owner thread that can paint and receive candidate clicks.
  MSG message{};
  PeekMessageW(&message, nullptr, WM_USER, WM_USER, PM_NOREMOVE);
  const DWORD ui_thread_id = GetCurrentThreadId();
  DebugStep(L"step: before engine");
  PinyinEngine engine(ModuleDirectory());
  DebugStep(L"step: engine ready");
  std::atomic_bool running{true};
  HANDLE stop_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  std::thread server(ServeRequests, &engine, &running, ui_thread_id, stop_event);
  DebugStep(L"step: server spawned");
  HostUi ui;
  TrayController tray(ModuleDirectory(), [&ui] { ui.ShowSettings(); });
  // Windows owns input switching and GY exposes its settings from the input UI.
  // Keep the tray entry diagnostic-only so a normal install never occupies a
  // permanent notification-area slot. Set GYINPUT_HOST_SHOW_TRAY=1 to opt in.
  const bool show_tray = GetEnvironmentVariableW(L"GYINPUT_HOST_SHOW_TRAY", nullptr, 0) > 0;
  if (show_tray) tray.Start();

  while (GetMessageW(&message, nullptr, 0, 0) > 0) {
    if (message.message == kUiCommandMessage) {
      auto* command = reinterpret_cast<UiCommand*>(message.wParam);
      ui.Apply(command);
      delete command;
      continue;
    }
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }

  running.store(false);
  // Wake the pooled pipe server so its WaitForMultipleObjects exits; pending
  // overlapped accepts are cancelled inside ServeRequests. The named pipe
  // server is never forcibly terminated, so no user process is touched.
  if (stop_event) SetEvent(stop_event);
  if (server.joinable()) server.join();
  if (stop_event) CloseHandle(stop_event);
  if (show_tray) tray.Stop();
  CloseHandle(single_instance);
  return 0;
}





