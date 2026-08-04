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

HANDLE CreateServerPipe() {
  // The IME Host can carry active composition data. Limit this IPC endpoint to
  // the owner of the Host process instead of accepting connections from other
  // local accounts. Remote clients are separately rejected by the pipe mode.
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(L"D:P(A;;GA;;;OW)", SDDL_REVISION_1,
                                                              &descriptor, nullptr)) {
    return INVALID_HANDLE_VALUE;
  }
  SECURITY_ATTRIBUTES attributes{sizeof(attributes), descriptor, FALSE};
  HANDLE pipe = CreateNamedPipeW(gy::host::HostPipeName().c_str(), PIPE_ACCESS_DUPLEX,
      PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
      1, gy::host::kMaxPayloadBytes, gy::host::kMaxPayloadBytes, 0, &attributes);
  LocalFree(descriptor);
  return pipe;
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

void ServeRequests(PinyinEngine* engine, std::atomic_bool* running, DWORD ui_thread_id) {
  if (!engine || !running) return;
  while (running->load()) {
    HANDLE pipe = CreateServerPipe();
    if (pipe == INVALID_HANDLE_VALUE) break;
    const BOOL connected = ConnectNamedPipe(pipe, nullptr) ? TRUE : GetLastError() == ERROR_PIPE_CONNECTED;
    if (connected) {
      gy::host::MessageType type{};
      std::wstring request;
      if (gy::host::ReadMessage(pipe, &type, &request)) {
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
        gy::host::WriteMessage(pipe, type, response);
        FlushFileBuffers(pipe);
      }
    }
    DisconnectNamedPipe(pipe);
    CloseHandle(pipe);
  }
}
}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  // Render at the active monitor DPI. Otherwise Windows virtualizes this GDI
  // surface at 96 DPI and 175% scaling makes Chinese glyphs look soft.
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  const std::wstring mutex_name = HostInstanceMutexName();
  HANDLE single_instance = CreateMutexW(nullptr, FALSE, mutex_name.c_str());
  if (!single_instance) return 2;
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(single_instance);
    return 0;
  }

  // Create the message queue before accepting IPC so queued UI commands always.
  // have an owner thread that can paint and receive candidate clicks.
  MSG message{};
  PeekMessageW(&message, nullptr, WM_USER, WM_USER, PM_NOREMOVE);
  const DWORD ui_thread_id = GetCurrentThreadId();
  PinyinEngine engine(ModuleDirectory());
  std::atomic_bool running{true};
  std::thread server(ServeRequests, &engine, &running, ui_thread_id);
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
  // A shutdown request closes the active pipe before this join. The named pipe
  // server is never forcibly terminated, so no user process is touched.
  if (server.joinable()) server.join();
  if (show_tray) tray.Stop();
  CloseHandle(single_instance);
  return 0;
}





