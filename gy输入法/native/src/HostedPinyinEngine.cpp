#include "HostedPinyinEngine.h"

#include "HostProtocol.h"
#include "PerformanceSettings.h"

#include <windows.h>

#include <algorithm>
#include <cwchar>
#include <cwctype>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace {

// How long a successful Host verification stays trusted. Within an active
// typing burst this removes the per-keystroke Status round trips entirely;
// a failed request always clears the stamp and forces a fresh handshake.
constexpr ULONGLONG kVerifiedHostTtlMs = 1500;

constexpr wchar_t kHostRegistryKey[] = L"SOFTWARE\\GYInput";

std::wstring JoinPath(const std::wstring& root, const wchar_t* child) {
  if (root.empty()) return child;
  return root.back() == L'\\' ? root + child : root + L"\\" + child;
}

bool FileExists(const std::wstring& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES && !(attributes & FILE_ATTRIBUTE_DIRECTORY);
}

bool IsKnownPinyinSyllable(const std::wstring& value) {
  // Rime accepts incomplete/fuzzy prefixes such as "ho" and may return a
  // one-character result for a longer query. RemainingPinyin is a parser, so
  // it needs the Mandarin syllable alphabet rather than a last-letter guess.
  // v is the conventional keyboard spelling of ü (lv, lve, nv, ...).
  static constexpr wchar_t kSyllables[] =
      L"|a|ai|an|ang|ao|ba|bai|ban|bang|bao|bei|ben|beng|bi|bian|biao|bie|bin|bing|bo|bu|"
      L"ca|cai|can|cang|cao|ce|cei|cen|ceng|cha|chai|chan|chang|chao|che|chen|cheng|chi|"
      L"chong|chou|chu|chua|chuai|chuan|chuang|chui|chun|chuo|ci|cong|cou|cu|cua|cuai|"
      L"cuan|cui|cun|cuo|da|dai|dan|dang|dao|de|dei|den|deng|di|dia|dian|diao|die|ding|"
      L"diu|dong|dou|du|dua|duan|dui|dun|duo|e|ei|en|eng|er|fa|fan|fang|fei|fen|feng|"
      L"fo|fou|fu|ga|gai|gan|gang|gao|ge|gei|gen|geng|gong|gou|gu|gua|guai|guan|gui|"
      L"gun|guo|ha|hai|han|hang|hao|he|hei|hen|heng|hong|hou|hu|hua|huai|huan|hui|hun|"
      L"huo|ji|jia|jian|jiang|jiao|jie|jin|jing|jiong|jiu|ju|juan|jue|jun|ka|kai|kan|"
      L"kang|kao|ke|kei|ken|keng|kong|kou|ku|kua|kuai|kuan|kui|kun|kuo|la|lai|lan|lang|"
      L"lao|le|lei|leng|li|lia|lian|liang|liao|lie|lin|ling|liu|long|lou|lu|lua|luan|lue|"
      L"lui|lun|luo|lv|lvan|lve|ma|mai|man|mang|mao|me|mei|men|meng|mi|mian|miao|mie|min|"
      L"ming|miu|mo|mou|mu|na|nai|nan|nang|nao|ne|nei|nen|neng|ni|nian|niang|niao|nie|"
      L"nin|ning|niu|nong|nou|nu|nuan|nuo|nv|nve|o|ou|pa|pai|pan|pang|pao|pei|pen|peng|"
      L"pi|pian|piao|pie|pin|ping|po|pou|pu|qi|qia|qian|qiang|qiao|qie|qin|qing|qiong|"
      L"qiu|qu|quan|que|qun|ran|rang|rao|re|ren|reng|ri|rong|rou|ru|rua|ruan|rui|run|"
      L"ruo|sa|sai|san|sang|sao|se|sei|sen|seng|sha|shai|shan|shang|shao|she|shei|shen|"
      L"sheng|shi|shou|shu|shua|shuai|shuan|shui|shun|shuo|si|song|sou|su|suan|sui|sun|"
      L"suo|ta|tai|tan|tang|tao|te|teng|ti|tian|tiao|tie|ting|tong|tou|tu|tuan|tui|tun|"
      L"tuo|wa|wai|wan|wang|wei|wen|weng|wo|wu|xi|xia|xian|xiang|xiao|xie|xin|xing|"
      L"xiong|xiu|xu|xuan|xue|xun|ya|yan|yang|yao|ye|yi|yin|ying|yo|yong|you|yu|yuan|"
      L"yue|yun|za|zai|zan|zang|zao|ze|zei|zen|zeng|zha|zhai|zhan|zhang|zhao|zhe|zhei|"
      L"zhen|zheng|zhi|zhong|zhou|zhu|zhua|zhuai|zhuan|zhui|zhun|zhuo|zi|zong|zou|zu|"
      L"zuan|zui|zun|zuo|";
  std::wstring normalized = value;
  std::transform(normalized.begin(), normalized.end(), normalized.begin(), [](wchar_t ch) {
    return static_cast<wchar_t>(towlower(ch));
  });
  const std::wstring needle = L"|" + normalized + L"|";
  return wcsstr(kSyllables, needle.c_str()) != nullptr;
}

bool CanParsePinyinPrefix(const std::wstring& value, size_t syllable_count) {
  if (value.empty() || syllable_count == 0) return false;
  std::wstring normalized;
  normalized.reserve(value.size());
  for (const wchar_t character : value) {
    if (character == L'\'') continue;
    normalized.push_back(static_cast<wchar_t>(towlower(character)));
  }
  if (normalized.empty()) return false;

  // Dynamic programming handles ambiguous spellings such as xian (xian or
  // xi-an) and selects the interpretation matching the selected Han text.
  std::vector<std::vector<bool>> reachable(
      normalized.size() + 1, std::vector<bool>(syllable_count + 1, false));
  reachable[0][0] = true;
  for (size_t offset = 0; offset < normalized.size(); ++offset) {
    for (size_t count = 0; count < syllable_count; ++count) {
      if (!reachable[offset][count]) continue;
      for (size_t length = 1; length <= 6 && offset + length <= normalized.size(); ++length) {
        if (IsKnownPinyinSyllable(normalized.substr(offset, length))) {
          reachable[offset + length][count + 1] = true;
        }
      }
    }
  }
  return reachable[normalized.size()][syllable_count];
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

bool CurrentProcessElevated() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return false;
  TOKEN_ELEVATION elevation{};
  DWORD size = sizeof(elevation);
  const bool elevated = GetTokenInformation(token, TokenElevation, &elevation, size, &size) &&
                        elevation.TokenIsElevated != 0;
  CloseHandle(token);
  return elevated;
}

bool StartHost(const std::wstring& path) {
  if (!FileExists(path)) return false;
  // An elevated launch poisons the whole install: objects created by an
  // elevated process are owned by the Administrators group, while the Host
  // pipe DACL grants the user — every medium-integrity app then gets
  // ACCESS_DENIED (compositions work, lookups die, the IME feels dead).
  // Elevated clients can still USE an existing Host (their token user is the
  // same account); they must just never be the process that creates it.
  if (CurrentProcessElevated()) return false;
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


bool IsExpectedHostStatus(const std::wstring& payload, const std::wstring& expected_version) {
  gy::host::HostStatus status{};
  if (!gy::host::DecodeStatus(payload, &status)) return false;
  return (expected_version.empty() || status.host_version == expected_version) &&
      status.protocol_version == gy::host::kProtocolVersion;
}

bool WaitForHostVersion(const std::wstring& expected_version, DWORD timeout_ms) {
  const ULONGLONG deadline = GetTickCount64() + timeout_ms;
  do {
    std::wstring status;
    if (SendRequest(gy::host::MessageType::Status, L"", &status) &&
        IsExpectedHostStatus(status, expected_version)) return true;
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
    // Fast path: a Host verified moments ago is almost certainly still alive.
    // Steady-state keystrokes skip the Status round trip entirely (Lookup and
    // ShowCandidates each used to pay one). Any failed request clears this
    // stamp, so a dead Host is detected on the very next key.
    // Warm start off (settings panel, low-spec mode) disables this keep-alive
    // cache; the setting is re-read at most once per TTL window per process.
    const ULONGLONG now = GetTickCount64();
    if (last_verified_tick != 0 && now - last_verified_tick < kVerifiedHostTtlMs &&
        gy::performance::WarmStartEnabled()) return true;
    const std::wstring expected_version = HostVersion();
    std::wstring status;
    if (SendRequest(gy::host::MessageType::Status, L"", &status)) {
      if (IsExpectedHostStatus(status, expected_version)) {
        last_verified_tick = now;
        return true;
      }
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
    if (WaitForHostVersion(expected_version, 900)) {
      last_verified_tick = GetTickCount64();
      return true;
    }
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
  ULONGLONG last_verified_tick = 0;
};

HostedPinyinEngine::HostedPinyinEngine(std::wstring module_directory)
    : impl_(std::make_unique<Impl>(std::move(module_directory))) {}
HostedPinyinEngine::~HostedPinyinEngine() = default;

std::vector<std::wstring> HostedPinyinEngine::Lookup(const std::wstring& pinyin) {
  if (!impl_ || pinyin.empty()) return {};
  std::scoped_lock lock(impl_->mutex);
  for (int attempt = 0; attempt < 2; ++attempt) {
    if (!impl_->EnsureHost()) break;
    std::wstring encoded;
    if (SendRequest(gy::host::MessageType::Lookup, pinyin, &encoded)) {
      impl_->last_verified_tick = GetTickCount64();
      impl_->diagnostic = L"using versioned GY Host";
      return gy::host::DecodeCandidates(encoded);
    }
    // The cached verification was stale (Host died between keystrokes): drop
    // it and retry once with a fresh handshake before giving up this key.
    impl_->last_verified_tick = 0;
  }
  impl_->diagnostic = L"GY Host unavailable";
  return {};
}
std::vector<std::wstring> HostedPinyinEngine::LookupExact(const std::wstring& pinyin) {
  if (!impl_ || pinyin.empty()) return {};
  std::scoped_lock lock(impl_->mutex);
  for (int attempt = 0; attempt < 2; ++attempt) {
    if (!impl_->EnsureHost()) break;
    std::wstring encoded;
    if (SendRequest(gy::host::MessageType::LookupExact, pinyin, &encoded)) {
      impl_->last_verified_tick = GetTickCount64();
      impl_->diagnostic = L"using versioned GY Host";
      return gy::host::DecodeCandidates(encoded);
    }
    impl_->last_verified_tick = 0;
  }
  impl_->diagnostic = L"GY Host unavailable";
  return {};
}
std::wstring HostedPinyinEngine::RemainingPinyin(const std::wstring& pinyin,
                                                 const std::wstring& candidate) {
  if (!impl_ || pinyin.empty() || candidate.empty()) return {};
  // Query complete prefixes from longest to shortest. Rime accepts some
  // incomplete syllables (for example "ho" as a usable prefix for 厚), so a
  // shortest-first search would consume too little and turn houyi into uyi.
  // The longest exact match preserves the whole syllable whenever Rime can
  // resolve it. Apostrophes are separators, not part of the suffix presented
  // to the next composition.
  for (size_t prefix_end = pinyin.size() - 1; prefix_end > 0; --prefix_end) {
    if (pinyin[prefix_end - 1] == L'\'') continue;
    if (!CanParsePinyinPrefix(pinyin.substr(0, prefix_end), candidate.size())) continue;
    const size_t remainder_start =
        prefix_end < pinyin.size() && pinyin[prefix_end] == L'\'' ? prefix_end + 1 : prefix_end;
    if (remainder_start >= pinyin.size()) continue;
    // Lookup() intentionally appends shorter-prefix fallback candidates to
    // fill the 5x5 panel. That is useful for UI density but unsafe here: a
    // fallback candidate must not make us consume an incomplete syllable such
    // as "ho" from "houyi". Use the exact Host query for segmentation.
    const auto prefix_candidates = LookupExact(pinyin.substr(0, prefix_end));
    if (std::find(prefix_candidates.begin(), prefix_candidates.end(), candidate) != prefix_candidates.end()) {
      return pinyin.substr(remainder_start);
    }
  }
  return {};
}
void HostedPinyinEngine::Learn(const std::wstring& pinyin, const std::wstring& candidate) {
  if (!impl_ || pinyin.empty() || candidate.empty()) return;
  std::scoped_lock lock(impl_->mutex);
  // Fire-and-forget: recording a preference must never stall the commit edit
  // session. Only write when a Host was verified moments ago (never start one
  // just for learning), and intentionally do not read the response; bytes
  // already in the pipe buffer are delivered before the Host sees the close.
  const ULONGLONG now = GetTickCount64();
  if (impl_->last_verified_tick == 0 || now - impl_->last_verified_tick >= kVerifiedHostTtlMs) return;
  HANDLE pipe = OpenHostPipe(30);
  if (pipe == INVALID_HANDLE_VALUE) return;
  gy::host::WriteMessage(pipe, gy::host::MessageType::LearnCandidate,
                         gy::host::EncodeLearningEvent(pinyin, candidate));
  CloseHandle(pipe);
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
                                        unsigned selected, unsigned page_start, int input_mode, bool expanded, const std::wstring& callback_pipe) {
  if (!impl_ || candidates.empty()) { HideCandidates(); return; }
  std::scoped_lock lock(impl_->mutex);
  gy::host::CandidateUiState state{};
  state.caret = caret;
  state.candidates = candidates;
  state.selected = selected;
  state.page_start = page_start;
  state.input_mode = static_cast<unsigned>(input_mode < 0 ? 0 : input_mode > 2 ? 2 : input_mode);
  state.expanded = expanded;
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

void HostedPinyinEngine::ShowMode(const RECT& caret, int input_mode) {
  if (!impl_) return;
  std::scoped_lock lock(impl_->mutex);
  gy::host::CandidateUiState state{};
  state.caret = caret;
  state.input_mode = static_cast<unsigned>(input_mode < 0 ? 0 : input_mode > 2 ? 2 : input_mode);
  state.selected = state.input_mode;
  state.candidates = {state.input_mode == 2 ? L"EN" : (state.input_mode == 1 ? L"繁" : L"中")};
  if (!impl_->SendUi(gy::host::MessageType::ShowMode, gy::host::EncodeCandidateUi(state), true)) {
    impl_->diagnostic = L"GY Host mode UI is unavailable";
  }
}
