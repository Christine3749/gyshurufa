#include "CandidateWindow.h"
#include "ClipboardHistory.h"
#include "GyKeepSync.h"
#include "HostProtocol.h"
#include "PerformanceSettings.h"
#include "PinyinEngine.h"
#include "SettingsWindow.h"
#include "TrayController.h"
#include "UpdateNotification.h"

#include <windows.h>
#include <sddl.h>

#include <atomic>
#include <string>
#include <thread>
#include <iterator>
#include <vector>

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

// 本机剪贴板历史（CLIPBOARD-PAGE-DESIGN.md）：一个 message-only 隐藏窗口接收
// WM_CLIPBOARDUPDATE，与候选窗/设置窗共用这条 UI 消息循环。纯本地、零网络。
LRESULT CALLBACK ClipboardListenerProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_CLIPBOARDUPDATE) {
    if (gy::clipboard_history::AppendFromClipboard()) {
      gy::keep_sync::NotifyLocalClipboardChanged();
    }
    return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

HWND CreateClipboardListener() {
  constexpr wchar_t kClassName[] = L"GyImeHostClipboard";
  static const ATOM atom = [] {
    WNDCLASSEXW wc{sizeof(wc)};
    wc.lpfnWndProc = ClipboardListenerProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = kClassName;
    return RegisterClassExW(&wc);
  }();
  if (!atom) return nullptr;
  return CreateWindowExW(0, kClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr,
                         GetModuleHandleW(nullptr), nullptr);
}

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

std::wstring ParentDirectory(const std::wstring& path) {
  const size_t slash = path.find_last_of(L"\\/");
  return slash == std::wstring::npos ? std::wstring{} : path.substr(0, slash);
}

std::wstring ReadUtf8TextFile(const std::wstring& path) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return {};
  LARGE_INTEGER size{};
  if (!GetFileSizeEx(file, &size) || size.QuadPart <= 0 || size.QuadPart > 64 * 1024) {
    CloseHandle(file);
    return {};
  }
  std::vector<char> bytes(static_cast<size_t>(size.QuadPart));
  DWORD read = 0;
  const bool ok = ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr) != FALSE;
  CloseHandle(file);
  if (!ok || read == 0) return {};
  size_t offset = 0;
  if (read >= 3 && static_cast<unsigned char>(bytes[0]) == 0xEF &&
      static_cast<unsigned char>(bytes[1]) == 0xBB && static_cast<unsigned char>(bytes[2]) == 0xBF) {
    offset = 3;
  }
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, bytes.data() + offset,
                                         static_cast<int>(read - offset), nullptr, 0);
  if (length <= 0) return {};
  std::wstring result(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, bytes.data() + offset,
                      static_cast<int>(read - offset), result.data(), length);
  return result;
}

std::wstring ReadUpdateStateValue(const wchar_t* name) {
  wchar_t local_app_data[MAX_PATH]{};
  const DWORD length = GetEnvironmentVariableW(L"LOCALAPPDATA", local_app_data,
                                                static_cast<DWORD>(std::size(local_app_data)));
  if (length == 0 || length >= std::size(local_app_data)) return {};
  const std::wstring raw = ReadUtf8TextFile(std::wstring(local_app_data, length) + L"\\GYInput\\update-state.ini");
  const std::wstring prefix = std::wstring(name) + L"=";
  size_t begin = 0;
  while (begin <= raw.size()) {
    const size_t end = raw.find_first_of(L"\r\n", begin);
    const std::wstring line = raw.substr(begin, end == std::wstring::npos ? std::wstring::npos : end - begin);
    if (line.rfind(prefix, 0) == 0) return line.substr(prefix.size());
    if (end == std::wstring::npos) break;
    begin = raw.find_first_not_of(L"\r\n", end);
    if (begin == std::wstring::npos) break;
  }
  return {};
}

std::wstring UpdateNotificationMarkerPath() {
  wchar_t local_app_data[MAX_PATH]{};
  const DWORD length = GetEnvironmentVariableW(L"LOCALAPPDATA", local_app_data,
                                                static_cast<DWORD>(std::size(local_app_data)));
  if (length == 0 || length >= std::size(local_app_data)) return {};
  return std::wstring(local_app_data, length) + L"\\GYInput\\update-notified.txt";
}

bool UpdateNotificationAlreadyShown(const std::wstring& version) {
  return !version.empty() && ReadUtf8TextFile(UpdateNotificationMarkerPath()) == version;
}

void MarkUpdateNotificationShown(const std::wstring& version) {
  const std::wstring path = UpdateNotificationMarkerPath();
  if (path.empty() || version.empty()) return;
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_HIDDEN, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  std::string ascii;
  ascii.reserve(version.size());
  for (const wchar_t character : version) {
    if (character > 0x7F) {
      CloseHandle(file);
      return;
    }
    ascii.push_back(static_cast<char>(character));
  }
  DWORD written = 0;
  WriteFile(file, ascii.data(), static_cast<DWORD>(ascii.size()), &written, nullptr);
  CloseHandle(file);
}

bool SetCurrentUserRegistryString(const wchar_t* subkey, const wchar_t* value_name,
                                  const std::wstring& value) {
  HKEY key = nullptr;
  DWORD disposition = 0;
  const LONG open_result = RegCreateKeyExW(HKEY_CURRENT_USER, subkey, 0, nullptr, 0,
                                           KEY_SET_VALUE, nullptr, &key, &disposition);
  if (open_result != ERROR_SUCCESS || !key) return false;
  const BYTE* data = reinterpret_cast<const BYTE*>(value.c_str());
  const DWORD bytes = static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));
  const LONG write_result = RegSetValueExW(key, value_name, 0, REG_SZ, data, bytes);
  RegCloseKey(key);
  return write_result == ERROR_SUCCESS;
}

void RegisterGyInputProtocol(const std::wstring& powershell, const std::wstring& script) {
  // Register per-user so the toast action works without an additional UAC
  // prompt and an older version's uninstaller cannot remove this protocol.
  const std::wstring command = L"\"" + powershell +
      L"\" -NoProfile -ExecutionPolicy Bypass -File \"" + script +
      L"\" -ToastActionUri \"%1\"";
  SetCurrentUserRegistryString(L"Software\\Classes\\gyinput", nullptr,
                               L"URL:GY Input Update");
  SetCurrentUserRegistryString(L"Software\\Classes\\gyinput", L"URL Protocol", L"");
  SetCurrentUserRegistryString(L"Software\\Classes\\gyinput\\shell\\open\\command", nullptr,
                               command);
}

void MaybeShowUpdateNotification() {
  const std::wstring status = ReadUpdateStateValue(L"status");
  const std::wstring version = ReadUpdateStateValue(L"version");
  if (status != L"update-available" || version.empty() || UpdateNotificationAlreadyShown(version)) return;
  if (ShowGyUpdateNotification(version)) MarkUpdateNotificationShown(version);
}

void StartAutomaticUpdateCheck(const std::wstring& module_directory) {
#ifdef GY_TESTING
  // Unit/smoke Hosts must never make network requests or create user state.
  (void)module_directory;
#else
  if (GetEnvironmentVariableW(L"GYINPUT_DISABLE_UPDATE_CHECK", nullptr, 0) > 0) return;
  const std::wstring version_root = module_directory;
  const std::wstring versions_root = ParentDirectory(version_root);
  const std::wstring install_root = ParentDirectory(versions_root);
  if (install_root.empty()) return;
  const std::wstring script = install_root + L"\\AutoUpdate-GYInput.ps1";
  if (GetFileAttributesW(script.c_str()) == INVALID_FILE_ATTRIBUTES) return;

  wchar_t windows_directory[MAX_PATH]{};
  const UINT length = GetWindowsDirectoryW(windows_directory, static_cast<UINT>(std::size(windows_directory)));
  if (length == 0 || length >= std::size(windows_directory)) return;
  const std::wstring powershell = std::wstring(windows_directory, length) +
      L"\\System32\\WindowsPowerShell\\v1.0\\powershell.exe";
  RegisterGyInputProtocol(powershell, script);
  std::thread([powershell, script]() {
    std::wstring command = L"\"" + powershell + L"\" -NoProfile -ExecutionPolicy Bypass -File \"" + script + L"\" -Action Check";
    std::vector<wchar_t> mutable_command(command.begin(), command.end());
    mutable_command.push_back(L'\0');
    STARTUPINFOW startup{sizeof(startup)};
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(nullptr, mutable_command.data(), nullptr, nullptr, FALSE,
                        CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT, nullptr, nullptr,
                        &startup, &process)) return;
    const DWORD wait = WaitForSingleObject(process.hProcess, 60000);
    if (wait == WAIT_OBJECT_0) MaybeShowUpdateNotification();
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
  }).detach();
#endif
}

constexpr DWORD kPipeInstanceCount = 8;

SECURITY_ATTRIBUTES* PipeSecurityAttributes() {
  // Cached for the process lifetime. Parsing the SDDL used to happen on every
  // single client connection and was part of the ~15ms accept-recycle cost.
  static SECURITY_ATTRIBUTES* cached = [] {
    // Grant the interactive user explicitly instead of only the pipe owner:
    // objects created by an elevated process are owned by the Administrators
    // group, so an owner-only DACL locks out every medium-integrity app when
    // the Host was ever launched elevated. The user SID comes from our own
    // token, which does not change with elevation. Other local users are
    // still denied either way.
    //
    // Two extra entries keep packaged apps (Win11 SearchHost, Start, lock
    // screen) functional. They run AppContainer tokens at low integrity, so:
    //  1. (A;;GRGW;;;S-1-15-2-1) grants ALL APPLICATION PACKAGES read/write.
    //     Package identity is per-user, and the user-SID ACE below still
    //     scopes the pipe to this account, so this adds no cross-user access.
    //  2. S:(ML;;NW;;;LW) labels the pipe low-integrity with No-Write-Up.
    //     Without it a kernel default medium label silently rejects writes
    //     from every low-integrity (packaged) client no matter what the
    //     DACL says — that was the Win-key search box showing compositions
    //     but never a candidate window.
    constexpr wchar_t kPackageAndLabel[] = L"(A;;GRGW;;;S-1-15-2-1)";
    constexpr wchar_t kLowIntegrityPolicy[] = L"S:(ML;;NW;;;LW)";
    std::wstring sddl = std::wstring(L"D:P(A;;GA;;;OW)") + kPackageAndLabel + kLowIntegrityPolicy;
    HANDLE token = nullptr;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
      DWORD size = 0;
      GetTokenInformation(token, TokenUser, nullptr, 0, &size);
      std::vector<unsigned char> buffer(size);
      if (size && GetTokenInformation(token, TokenUser, buffer.data(), size, &size)) {
        wchar_t* sid_string = nullptr;
        if (ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(buffer.data())->User.Sid,
                                   &sid_string)) {
          sddl = L"D:P(A;;GA;;;" + std::wstring(sid_string) + L")" + kPackageAndLabel + kLowIntegrityPolicy;
          LocalFree(sid_string);
        }
      }
      CloseHandle(token);
    }
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.c_str(), SDDL_REVISION_1,
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
  } else if (type == gy::host::MessageType::LookupExact) {
    response = gy::host::EncodeCandidates(engine->LookupExact(request));
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
  // Warm start off (low-spec mode) falls back to a single pre-accepted
  // instance; the setting is read once at Host startup.
  const size_t instance_count = gy::performance::WarmStartEnabled() ? kPipeInstanceCount : 1;
  std::vector<PipeListener> listeners(instance_count);
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
  // 剪贴板历史监听挂在本线程的消息循环上；失败不致命，仅失去历史记录。
  HWND clipboard_listener = CreateClipboardListener();
  if (clipboard_listener && !AddClipboardFormatListener(clipboard_listener)) {
    DestroyWindow(clipboard_listener);
    clipboard_listener = nullptr;
  }
  gy::keep_sync::Start();
  DebugStep(L"step: before engine");
  PinyinEngine engine(ModuleDirectory());
  DebugStep(L"step: engine ready");
  StartAutomaticUpdateCheck(ModuleDirectory());
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

  gy::keep_sync::Stop();
  if (clipboard_listener) {
    RemoveClipboardFormatListener(clipboard_listener);
    DestroyWindow(clipboard_listener);
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





