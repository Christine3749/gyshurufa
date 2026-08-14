// GyHostPerf — keystroke-path latency benchmark for the DLL <-> Host pipe.
//
// It reproduces exactly what the TSF DLL does today for ONE keystroke:
//   1. EnsureHost   -> connect + Status request + close
//   2. Lookup       -> connect + Lookup request + close
//   3. ShowCandidates -> (EnsureHost again) + connect + Show request + close
// Every stage is timed with QueryPerformanceCounter so we can see where the
// milliseconds go before and after the IPC optimizations.
//
// Everything runs against an isolated test Host (private pipe, temp
// LOCALAPPDATA, no tray), never the live user Host. The candidate window is
// anchored off-screen so the benchmark does not flash UI on the desktop.

#include "HostProtocol.h"
#include "NativeTestInputMode.h"

#include <windows.h>

#include <algorithm>
#include <iostream>
#include <string>
#include <vector>

namespace {

struct Stopwatch {
  static double Frequency() {
    static double freq = [] {
      LARGE_INTEGER f{};
      QueryPerformanceFrequency(&f);
      return 1000000.0 / static_cast<double>(f.QuadPart);  // ticks -> microseconds
    }();
    return freq;
  }
  static double NowUs() {
    LARGE_INTEGER t{};
    QueryPerformanceCounter(&t);
    return static_cast<double>(t.QuadPart) * Frequency();
  }
};

bool UseIsolatedHostEnvironment(const std::wstring& suffix) {
  wchar_t temp[MAX_PATH]{};
  const DWORD length = GetTempPathW(MAX_PATH, temp);
  if (!length || length >= MAX_PATH) return false;
  const std::wstring local = std::wstring(temp) + L"GYInput-HostPerf-" + suffix;
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
  const std::wstring result(path, length);
  const size_t slash = result.find_last_of(L"\\/");
  return slash == std::wstring::npos ? std::wstring{} : result.substr(0, slash);
}

PROCESS_INFORMATION StartHost(const std::wstring& directory) {
  PROCESS_INFORMATION process{};
  const std::wstring host = directory + L"\\GyImeHost.exe";
  std::wstring command = L"\"" + host + L"\"";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  if (!CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr,
                      directory.c_str(), &startup, &process)) {
    process.hProcess = nullptr;
    return process;
  }
  CloseHandle(process.hThread);
  return process;
}

// One full "connect -> request -> response -> close" cycle, exactly what
// HostedPinyinEngine::SendRequest does today. Reports open and request
// latency separately.
bool Roundtrip(gy::host::MessageType type, const std::wstring& payload, double* open_us,
               double* request_us) {
  const double t0 = Stopwatch::NowUs();
  HANDLE pipe = INVALID_HANDLE_VALUE;
  const ULONGLONG deadline = GetTickCount64() + 5000;
  do {
    if (WaitNamedPipeW(gy::host::HostPipeName().c_str(), 25)) {
      pipe = CreateFileW(gy::host::HostPipeName().c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                         OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
      if (pipe != INVALID_HANDLE_VALUE) break;
    }
    Sleep(1);
  } while (GetTickCount64() < deadline);
  const double t1 = Stopwatch::NowUs();
  if (pipe == INVALID_HANDLE_VALUE) return false;

  gy::host::MessageType response_type{};
  std::wstring response;
  const bool ok = gy::host::WriteMessage(pipe, type, payload) &&
                  gy::host::ReadMessage(pipe, &response_type, &response) && response_type == type;
  const double t2 = Stopwatch::NowUs();
  CloseHandle(pipe);
  *open_us = t1 - t0;
  *request_us = t2 - t1;
  return ok;
}

struct Stats {
  std::wstring name;
  std::vector<double> samples;
  void Print() const {
    std::vector<double> sorted = samples;
    std::sort(sorted.begin(), sorted.end());
    const auto pick = [&](double q) { return sorted[static_cast<size_t>(q * (sorted.size() - 1))]; };
    double sum = 0;
    for (const double v : sorted) sum += v;
    std::wcout << L"  " << name << L": p50=" << pick(0.50) << L"us  p95=" << pick(0.95)
               << L"us  max=" << sorted.back() << L"us  mean=" << (sum / sorted.size()) << L"us\n";
  }
};

}  // namespace

int wmain() {
  const std::wstring suffix = std::to_wstring(GetCurrentProcessId());
  if (!UseIsolatedHostEnvironment(suffix)) {
    std::wcerr << L"Cannot prepare isolated Host environment.\n";
    return 4;
  }
  const gy::test::ScopedInputMode simplified_mode(gy::input_mode::kSimplified);
  const std::wstring lookup_payload = gy::host::EncodeLookupRequest({L"nihao", 0, 1});
  const std::wstring directory = ModuleDirectory();
  PROCESS_INFORMATION host = StartHost(directory);
  if (!host.hProcess) {
    std::wcerr << L"Cannot start GyImeHost.\n";
    return 1;
  }

  // Wait until the isolated Host answers Status.
  bool ready = false;
  for (int i = 0; i < 200 && !ready; ++i) {
    double open_us = 0, request_us = 0;
    ready = Roundtrip(gy::host::MessageType::Status, L"", &open_us, &request_us);
    if (!ready) Sleep(50);
  }
  if (!ready) {
    std::wcerr << L"Isolated Host did not come up.\n";
    TerminateProcess(host.hProcess, 1);
    CloseHandle(host.hProcess);
    return 5;
  }

  // Warm-up: let rime finish lazy-loading tables so we measure steady state.
  for (int i = 0; i < 30; ++i) {
    double open_us = 0, request_us = 0;
    Roundtrip(gy::host::MessageType::Lookup, lookup_payload, &open_us, &request_us);
  }

  constexpr int kIterations = 300;
  Stats status_open{L"status open  "}, status_req{L"status req   "};
  Stats lookup_open{L"lookup open  "}, lookup_req{L"lookup req   "};
  Stats show_open{L"show open    "}, show_req{L"show req     "};
  Stats keystroke{L"KEYSTROKE 4-cycle total"};
  Stats fused{L"FUSED 1-cycle estimate"};

  // Typical candidate payload: 9 candidates incl. one long word, anchored
  // off-screen so nothing flashes on the desktop during the run.
  gy::host::CandidateUiState ui{};
  ui.caret = RECT{-3000, -3000, -2999, -2980};
  ui.candidates = {L"你好", L"你", L"拟", L"泥", L"逆", L"尼", L"腻", L"匿", L"下一个版本候选词"};
  ui.selected = 0;
  ui.page_start = 0;
  ui.input_mode = 0;
  ui.chinese_grid_open = false;
  ui.callback_pipe = L"";
  const std::wstring show_payload = gy::host::EncodeCandidateUi(ui);

  for (int i = 0; i < kIterations; ++i) {
    double open_us = 0, request_us = 0;
    double total = 0;

    // 1) EnsureHost Status check (happens before every Lookup AND every Show).
    if (Roundtrip(gy::host::MessageType::Status, L"", &open_us, &request_us)) {
      status_open.samples.push_back(open_us);
      status_req.samples.push_back(request_us);
      total += open_us + request_us;
    }
    // 2) Lookup.
    if (Roundtrip(gy::host::MessageType::Lookup, lookup_payload, &open_us, &request_us)) {
      lookup_open.samples.push_back(open_us);
      lookup_req.samples.push_back(request_us);
      total += open_us + request_us;
    }
    // 3) Second EnsureHost Status + 4) ShowCandidates.
    if (Roundtrip(gy::host::MessageType::Status, L"", &open_us, &request_us)) {
      total += open_us + request_us;
    }
    if (Roundtrip(gy::host::MessageType::ShowCandidates, show_payload, &open_us, &request_us)) {
      show_open.samples.push_back(open_us);
      show_req.samples.push_back(request_us);
      total += open_us + request_us;
    }
    keystroke.samples.push_back(total);

    // Estimate of the fused path: a single connect + a single request whose
    // payload does lookup+show work inside the Host.
    if (Roundtrip(gy::host::MessageType::Lookup, lookup_payload, &open_us, &request_us)) {
      fused.samples.push_back(open_us + request_us);
    }
  }

  double open_us = 0, request_us = 0;
  Roundtrip(gy::host::MessageType::Shutdown, L"", &open_us, &request_us);
  WaitForSingleObject(host.hProcess, 5000);
  CloseHandle(host.hProcess);

  std::wcout << L"\n== GY IME keystroke latency baseline (" << kIterations << L" iterations) ==\n";
  status_open.Print();
  status_req.Print();
  lookup_open.Print();
  lookup_req.Print();
  show_open.Print();
  show_req.Print();
  std::wcout << L"\n";
  keystroke.Print();
  fused.Print();
  return 0;
}
