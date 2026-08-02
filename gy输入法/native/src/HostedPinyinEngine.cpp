#include "HostedPinyinEngine.h"

#include "HostProtocol.h"

#include <windows.h>

#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace {
constexpr wchar_t kHostRegistryKey[] = L"SOFTWARE\\GYInput";

std::wstring JoinPath(const std::wstring& root, const wchar_t* child) {
  if (root.empty()) return child;
  return root.back() == L'\\' ? root + child : root + L"\\" + child;
}

bool FileExists(const std::wstring& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES && !(attributes & FILE_ATTRIBUTE_DIRECTORY);
}

std::wstring ReadMachineValue(const wchar_t* name) {
#ifdef GY_TESTING
  const wchar_t* environment_name = wcscmp(name, L"HostPath") == 0 ? L"GYINPUT_HOST_PATH" :
      wcscmp(name, L"HostVersion") == 0 ? L"GYINPUT_HOST_VERSION" : nullptr;
  if (environment_name) {
    wchar_t value[MAX_PATH]{};
    const DWORD length = GetEnvironmentVariableW(environment_name, value, static_cast<DWORD>(std::size(value)));
    if (length && length < std::size(value)) return std::wstring(value, length);
  }
#endif
  DWORD bytes = 0;
  if (RegGetValueW(HKEY_LOCAL_MACHINE, kHostRegistryKey, name, RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY,
                   nullptr, nullptr, &bytes) != ERROR_SUCCESS || bytes < sizeof(wchar_t)) return {};
  std::wstring value(bytes / sizeof(wchar_t), L'\0');
  if (RegGetValueW(HKEY_LOCAL_MACHINE, kHostRegistryKey, name, RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY,
                   nullptr, value.data(), &bytes) != ERROR_SUCCESS) return {};
  while (!value.empty() && value.back() == L'\0') value.pop_back();
  return value;
}

HANDLE OpenHostPipe(DWORD timeout_ms) {
  const ULONGLONG deadline = GetTickCount64() + timeout_ms;
  do {
    if (WaitNamedPipeW(gy::host::HostPipeName().c_str(), 25)) {
      HANDLE pipe = CreateFileW(gy::host::HostPipeName().c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
                                FILE_ATTRIBUTE_NORMAL, nullptr);
      if (pipe != INVALID_HANDLE_VALUE) return pipe;
    }
    Sleep(5);
  } while (GetTickCount64() < deadline);
  return INVALID_HANDLE_VALUE;
}

bool SendRequest(gy::host::MessageType type, const std::wstring& payload, std::wstring* response) {
  HANDLE pipe = OpenHostPipe(120);
  if (pipe == INVALID_HANDLE_VALUE) return false;
  const bool written = gy::host::WriteMessage(pipe, type, payload);
  gy::host::MessageType response_type{};
  const bool read = written && gy::host::ReadMessage(pipe, &response_type, response) && response_type == type;
  CloseHandle(pipe);
  return read;
}

bool StartHost(const std::wstring& path) {
  if (!FileExists(path)) return false;
  std::vector<wchar_t> command(path.begin(), path.end());
  command.push_back(L'\0');
  STARTUPINFOW startup{sizeof(startup)};
  PROCESS_INFORMATION process{};
  const BOOL started = CreateProcessW(path.c_str(), command.data(), nullptr, nullptr, FALSE,
                                      CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process);
  if (!started) return false;
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return true;
}

bool WaitForHostVersion(const std::wstring& expected_version, DWORD timeout_ms) {
  const ULONGLONG deadline = GetTickCount64() + timeout_ms;
  do {
    std::wstring actual_version;
    if (SendRequest(gy::host::MessageType::Status, L"", &actual_version) &&
        (expected_version.empty() || actual_version == expected_version)) return true;
    Sleep(15);
  } while (GetTickCount64() < deadline);
  return false;
}

bool WaitForHostExit(DWORD timeout_ms) {
  const ULONGLONG deadline = GetTickCount64() + timeout_ms;
  do {
    std::wstring ignored;
    if (!SendRequest(gy::host::MessageType::Status, L"", &ignored)) return true;
    Sleep(15);
  } while (GetTickCount64() < deadline);
  return false;
}
}  // namespace

struct HostedPinyinEngine::Impl {
  explicit Impl(std::wstring directory) : module_directory(std::move(directory)) {}

  std::wstring HostPath() const {
    const std::wstring registered = ReadMachineValue(L"HostPath");
    if (FileExists(registered)) return registered;
    return JoinPath(module_directory, L"GyImeHost.exe");
  }

  std::wstring HostVersion() const { return ReadMachineValue(L"HostVersion"); }

  bool EnsureHost() {
    const std::wstring expected_version = HostVersion();
    std::wstring actual_version;
    if (SendRequest(gy::host::MessageType::Status, L"", &actual_version)) {
      if (expected_version.empty() || actual_version == expected_version) return true;
      // A versioned Host is single-instance. During a Host-only update, wait
      // until the old owner has really released the pipe before starting the
      // new binary; otherwise the first composition can race the old mutex.
      std::wstring ignored;
      SendRequest(gy::host::MessageType::Shutdown, L"", &ignored);
      if (!WaitForHostExit(900)) {
        diagnostic = L"GY Host did not exit for an update";
        return false;
      }
    }
    if (!StartHost(HostPath())) {
      diagnostic = L"GY Host could not be started";
      return false;
    }
    // The initial lookup is allowed a short, bounded launch window. No text
    // is ever injected while the Host is unavailable; the TSF preedit remains
    // local and the next key retries this handshake.
    if (WaitForHostVersion(expected_version, 900)) return true;
    diagnostic = L"GY Host is starting or has a mismatched version";
    return false;
  }

  bool SendUi(gy::host::MessageType type, const std::wstring& payload, bool start_if_needed) {
    if (start_if_needed) {
      if (!EnsureHost()) return false;
    } else {
      std::wstring status;
      if (!SendRequest(gy::host::MessageType::Status, L"", &status)) return false;
    }
    std::wstring ignored;
    return SendRequest(type, payload, &ignored);
  }

  std::wstring module_directory;
  std::wstring diagnostic;
  std::mutex mutex;
};

HostedPinyinEngine::HostedPinyinEngine(std::wstring module_directory)
    : impl_(std::make_unique<Impl>(std::move(module_directory))) {}
HostedPinyinEngine::~HostedPinyinEngine() = default;

std::vector<std::wstring> HostedPinyinEngine::Lookup(const std::wstring& pinyin) {
  if (!impl_ || pinyin.empty()) return {};
  std::scoped_lock lock(impl_->mutex);
  if (impl_->EnsureHost()) {
    std::wstring encoded;
    if (SendRequest(gy::host::MessageType::Lookup, pinyin, &encoded)) {
      impl_->diagnostic = L"using versioned GY Host";
      return gy::host::DecodeCandidates(encoded);
    }
  }
  impl_->diagnostic = L"GY Host unavailable";
  return {};
}
void HostedPinyinEngine::Learn(const std::wstring& pinyin, const std::wstring& candidate) {
  if (!impl_ || pinyin.empty() || candidate.empty()) return;
  std::scoped_lock lock(impl_->mutex);
  // The Host is normally alive while a composition is being committed. Do not
  // start it or block this TSF edit path merely to record a preference.
  std::wstring ignored;
  SendRequest(gy::host::MessageType::LearnCandidate, gy::host::EncodeLearningEvent(pinyin, candidate), &ignored);
}

void HostedPinyinEngine::Prewarm() {
  if (!impl_) return;
  std::scoped_lock lock(impl_->mutex);
  std::wstring status;
  if (SendRequest(gy::host::MessageType::Status, L"", &status)) return;
  if (!StartHost(impl_->HostPath())) impl_->diagnostic = L"GY Host could not be prewarmed";
}
std::wstring HostedPinyinEngine::Diagnostic() const {
  return impl_ ? impl_->diagnostic : L"hosted engine implementation is unavailable";
}
void HostedPinyinEngine::ShowCandidates(const RECT& caret, const std::vector<std::wstring>& candidates,
                                        unsigned selected, unsigned page_start, const std::wstring& callback_pipe) {
  if (!impl_ || candidates.empty()) { HideCandidates(); return; }
  std::scoped_lock lock(impl_->mutex);
  gy::host::CandidateUiState state{};
  state.caret = caret;
  state.candidates = candidates;
  state.selected = selected;
  state.page_start = page_start;
  state.callback_pipe = callback_pipe;
  if (!impl_->SendUi(gy::host::MessageType::ShowCandidates, gy::host::EncodeCandidateUi(state), true)) {
    impl_->diagnostic = L"GY Host candidate UI is unavailable";
  }
}

void HostedPinyinEngine::HideCandidates() {
  if (!impl_) return;
  std::scoped_lock lock(impl_->mutex);
  impl_->SendUi(gy::host::MessageType::HideCandidates, L"", false);
}

void HostedPinyinEngine::ShowMode(const RECT& caret, bool english_mode) {
  if (!impl_) return;
  std::scoped_lock lock(impl_->mutex);
  gy::host::CandidateUiState state{};
  state.caret = caret;
  state.selected = english_mode ? 1u : 0u;
  state.candidates = {english_mode ? L"EN" : L"中"};
  if (!impl_->SendUi(gy::host::MessageType::ShowMode, gy::host::EncodeCandidateUi(state), true)) {
    impl_->diagnostic = L"GY Host mode UI is unavailable";
  }
}

