#include "HostProtocol.h"
#include "NativeTestInputMode.h"

#include <windows.h>

#include <iostream>
#include <string>
#include <vector>

namespace {
bool UseIsolatedHostEnvironment() {
  wchar_t temp[MAX_PATH]{};
  const DWORD length = GetTempPathW(MAX_PATH, temp);
  if (!length || length >= MAX_PATH) return false;
  const std::wstring suffix = std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64());
  const std::wstring local = std::wstring(temp) + L"GYInput-HostSmoke-" + suffix;
  if (!CreateDirectoryW(local.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) return false;
  const std::wstring pipe = L"\\\\.\\pipe\\GYInput.Host.test." + suffix;
  return SetEnvironmentVariableW(L"LOCALAPPDATA", local.c_str()) != FALSE &&
         SetEnvironmentVariableW(L"GYINPUT_HOST_PIPE", pipe.c_str()) != FALSE &&
         SetEnvironmentVariableW(L"GYINPUT_HOST_NO_TRAY", L"1") != FALSE;
}
std::wstring ModuleDirectory() {
  wchar_t path[MAX_PATH]{};
  const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (!length || length == MAX_PATH) return {};
  std::wstring result(path, length);
  const size_t slash = result.find_last_of(L"\\/");
  return slash == std::wstring::npos ? std::wstring{} : result.substr(0, slash);
}

bool Send(gy::host::MessageType type, const std::wstring& payload, std::vector<std::wstring>* result) {
  HANDLE pipe = INVALID_HANDLE_VALUE;
  const ULONGLONG deadline = GetTickCount64() + 30000;
  do {
    if (WaitNamedPipeW(gy::host::HostPipeName().c_str(), 25)) {
      pipe = CreateFileW(gy::host::HostPipeName().c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, 0, nullptr);
      if (pipe != INVALID_HANDLE_VALUE) break;
    }
    Sleep(5);
  } while (GetTickCount64() < deadline);
  if (pipe == INVALID_HANDLE_VALUE) {
    std::wcerr << L"Host pipe is unavailable: " << GetLastError() << L"\n";
    return false;
  }
  gy::host::MessageType response_type{};
  std::wstring response_payload;
  bool ok = gy::host::WriteMessage(pipe, type, payload) &&
                  gy::host::ReadMessage(pipe, &response_type, &response_payload) &&
                  response_type == type;
  if (!ok) std::wcerr << L"IPC request failed, error=" << GetLastError() << L" response="
                       << static_cast<unsigned int>(response_type) << L" bytes=" << response_payload.size() << L"\n";
  CloseHandle(pipe);
  if (ok && result) {
    if (type == gy::host::MessageType::Lookup || type == gy::host::MessageType::LookupExact) {
      gy::host::LookupRequest request{};
      gy::host::LookupResponse response{};
      ok = gy::host::DecodeLookupRequest(payload, &request) &&
          gy::host::DecodeLookupResponse(response_payload, &response) &&
          gy::host::MatchesLookupSnapshot(request, response);
      if (ok) *result = std::move(response.candidates);
    } else {
      *result = gy::host::DecodeCandidates(response_payload);
    }
  }
  return ok;
}

std::wstring LookupPayload(const std::wstring& text, unsigned input_mode,
                           std::uint64_t mode_generation) {
  return gy::host::EncodeLookupRequest({text, input_mode, mode_generation});
}
}  // namespace

int wmain() {
  if (!UseIsolatedHostEnvironment()) {
    std::wcerr << L"Cannot prepare an isolated Host test environment.\n";
    return 4;
  }
  const gy::test::ScopedInputMode simplified_mode(gy::input_mode::kSimplified);
  const std::wstring directory = ModuleDirectory();
  const std::wstring host = directory + L"\\GyImeHost.exe";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  std::wstring command = L"\"" + host + L"\"";
  if (!CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, directory.c_str(), &startup, &process)) {
    std::wcerr << L"Cannot start GyImeHost.\n";
    return 1;
  }
CloseHandle(process.hThread);
  // A failed Host must be reported immediately instead of turning into a
  // misleading 30-second pipe timeout.
  Sleep(80);
  if (WaitForSingleObject(process.hProcess, 0) == WAIT_OBJECT_0) {
    DWORD exit_code = 0;
    GetExitCodeProcess(process.hProcess, &exit_code);
    CloseHandle(process.hProcess);
    std::wcerr << L"GyImeHost exited during startup: " << exit_code << L"\n";
    return 5;
  }

  std::vector<std::wstring> status;
  std::vector<std::wstring> candidates;
  const bool status_ok = Send(gy::host::MessageType::Status, L"", &status);
  const bool lookup_ok = Send(gy::host::MessageType::Lookup, LookupPayload(L"nihao", 0, 1), &candidates);
  // Pick a non-default real Han candidate so the test can prove that a
  // preference changes only after three explicit selections.
  const std::wstring learned = candidates.size() > 1 ? candidates.back() : L"";
  const std::wstring learning_event = gy::host::EncodeLearningEvent(L"nihao", learned, 0);
  const bool learn_ok = !learned.empty() && Send(gy::host::MessageType::LearnCandidate, learning_event, nullptr);
  const bool repeated_learn_ok = learn_ok && Send(gy::host::MessageType::LearnCandidate, learning_event, nullptr);
  std::vector<std::wstring> twice_candidates;
  const bool twice_lookup_ok = Send(
      gy::host::MessageType::Lookup, LookupPayload(L"nihao", 0, 1), &twice_candidates);
  const bool third_learn_ok = repeated_learn_ok && Send(gy::host::MessageType::LearnCandidate, learning_event, nullptr);
  std::vector<std::wstring> learned_candidates;
  const bool learned_lookup_ok = Send(
      gy::host::MessageType::Lookup, LookupPayload(L"nihao", 0, 1), &learned_candidates);
  // Persistence deliberately remains Chinese. The immutable request snapshot
  // must still route EN to the English engine.
  std::vector<std::wstring> english_candidates;
  const bool english_lookup_ok = Send(
      gy::host::MessageType::Lookup, LookupPayload(L"wo", 2, 2), &english_candidates);
  std::vector<std::wstring> english_nonprefix_candidates;
  const bool english_nonprefix_ok = Send(
      gy::host::MessageType::Lookup, LookupPayload(L"zhongw", 2, 2), &english_nonprefix_candidates);
  if (status_ok && !status.empty()) std::wcerr << L"Host status: " << status.front() << L"\n";
  Send(gy::host::MessageType::Shutdown, L"", nullptr);
  WaitForSingleObject(process.hProcess, 5000);
  CloseHandle(process.hProcess);
  if (!lookup_ok || !repeated_learn_ok || !twice_lookup_ok || !third_learn_ok || !learned_lookup_ok ||
      !english_lookup_ok || !english_nonprefix_ok ||
      candidates.size() < 2 || twice_candidates.empty() || learned_candidates.empty() ||
      twice_candidates.front() == learned || learned_candidates.front() != learned || english_candidates.size() < 5 ||
      !english_nonprefix_candidates.empty() ||
      english_candidates[0] != L"word" || english_candidates[1] != L"work" ||
      english_candidates[2] != L"world" || english_candidates[3] != L"would" ||
      english_candidates[4] != L"woman") {
    std::wcerr << L"Host learning integration failed. lookup=" << lookup_ok << L" learn=" << learn_ok << L" learnedLookup=" << learned_lookup_ok << L" initialCount=" << candidates.size() << L" learnedCount=" << learned_candidates.size() << L" expectedLength=" << learned.size() << L" firstLength=" << (learned_candidates.empty() ? 0 : learned_candidates.front().size()) << L"\n";
    return 2;
  }
  std::wcout << learned_candidates.front() << L"\n";
  return 0;
}


