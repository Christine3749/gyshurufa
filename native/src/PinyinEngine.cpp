#include "PinyinEngine.h"
#include "InputMode.h"
#include "SettingsFile.h"

#include <windows.h>

#include <rime_api.h>

#include <algorithm>
#include <array>
#include <cwctype>
#include <mutex>
#include <string_view>
#include <utility>
#include <unordered_map>

#ifndef GY_RELEASE_VERSION
#define GY_RELEASE_VERSION "dev"
#endif

namespace {
std::wstring JoinPath(const std::wstring& root, const wchar_t* child) {
  if (root.empty()) return child;
  return root.back() == L'\\' ? root + child : root + L"\\" + child;
}

std::string Utf8(const std::wstring& text) {
  if (text.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  if (size <= 0) return {};
  std::string result(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), result.data(), size, nullptr, nullptr);
  return result;
}

std::wstring Wide(const char* text) {
  if (!text || !*text) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, text, -1, nullptr, 0);
  if (size <= 1) return {};
  std::wstring result(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text, -1, result.data(), size);
  result.pop_back();
  return result;
}

std::wstring SettingsPath() {
  wchar_t root[MAX_PATH]{};
  if (!GetEnvironmentVariableW(L"LOCALAPPDATA", root, MAX_PATH)) return {};
  return std::wstring(root) + L"\\GYInput\\settings.ini";
}

bool EnsureBundledWorkspace(const std::wstring& shared, const std::wstring& user) {
  const std::wstring source = JoinPath(shared, L"build");
  const std::wstring destination = JoinPath(user, L"build");
  if (!CreateDirectoryW(destination.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) return false;
  // This directory is generated data, not the user's dictionary or custom YAML.
  // Always replace every generated artifact before Rime initializes. The old
  // early-return preserved stale generated schemas indefinitely.
  constexpr std::array<const wchar_t*, 5> kWorkspaceFiles{
      L"default.yaml", L"luna_pinyin.prism.bin", L"luna_pinyin.reverse.bin", L"luna_pinyin.schema.yaml", L"luna_pinyin.table.bin"};
  for (const wchar_t* file : kWorkspaceFiles) {
    const std::wstring from = JoinPath(source, file);
    const std::wstring to = JoinPath(destination, file);
    if (GetFileAttributesW(from.c_str()) == INVALID_FILE_ATTRIBUTES ||
        !CopyFileW(from.c_str(), to.c_str(), FALSE)) {
      return false;
    }
  }
  return true;
}
bool EnsureUnicodeSettingsFile(const std::wstring& path) {
  return gy::settings_file::EnsureUnicodeIniFile(path);
}

std::wstring Trim(std::wstring value) {
  const size_t first = value.find_first_not_of(L" \t\r\n");
  if (first == std::wstring::npos) return {};
  const size_t last = value.find_last_not_of(L" \t\r\n");
  return value.substr(first, last - first + 1);
}

std::wstring NormalizeCode(std::wstring value) {
  value = Trim(std::move(value));
  std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
    return static_cast<wchar_t>(std::towlower(ch));
  });
  return value;
}

std::vector<std::wstring> ReadIniSection(const std::wstring& path, const wchar_t* section) {
  std::vector<wchar_t> buffer(32768, L'\0');
  GetPrivateProfileSectionW(section, buffer.data(), static_cast<DWORD>(buffer.size()), path.c_str());
  std::vector<std::wstring> rows;
  for (const wchar_t* current = buffer.data(); *current; current += wcslen(current) + 1) rows.emplace_back(current);
  return rows;
}

std::wstring NormalizeOutputScript(const std::wstring& value, int input_mode) {
  if (value.empty() || input_mode == 2) return value;
  const DWORD flags = input_mode == 1 ? LCMAP_TRADITIONAL_CHINESE : LCMAP_SIMPLIFIED_CHINESE;
  const int length = LCMapStringEx(LOCALE_NAME_USER_DEFAULT, flags, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr, 0);
  if (length <= 0) return value;
  std::wstring converted(static_cast<size_t>(length), L'\0');
  if (LCMapStringEx(LOCALE_NAME_USER_DEFAULT, flags, value.data(), static_cast<int>(value.size()), converted.data(), length, nullptr, nullptr, 0) <= 0) return value;
  return converted;
}

bool IsCjkIdeograph(wchar_t character) {
  return (character >= 0x3400 && character <= 0x4DBF) ||
         (character >= 0x4E00 && character <= 0x9FFF) ||
         (character >= 0xF900 && character <= 0xFAFF);
}

bool IsCandidateAcceptable(const std::wstring& candidate) {
  // The candidate strip is a Chinese writing surface. This gate excludes emoji,
  // private-use glyphs, and accidental symbol entries from old dictionaries.
  if (candidate.empty() || candidate.size() > 12) return false;
  return std::all_of(candidate.begin(), candidate.end(), IsCjkIdeograph);
}

bool IsDeepCandidateAcceptable(const std::wstring& candidate) {
  // Candidates after the first visible page are intentionally held to a higher
  // bar. Rime's tail normally contains isolated rare characters before it
  // contains useful phrases. Do not pad extra pages with those fragments:
  // keep only real, comfortably readable words/phrases and let the menu end
  // early when there are not enough of them.
  return IsCandidateAcceptable(candidate) && candidate.size() >= 2 && candidate.size() <= 8;
}

// The candidate window remains a 5 × 5 page. The first page uses the IME
// engine's normal ranking; pages two and three only use qualified phrases.
// There is no minimum: a query with six good results returns six, not 75
// padded slots. The larger raw scan leaves room for filtering the tail.
constexpr int kRawCandidateScanLimit = 96;
constexpr size_t kPrimaryCandidateLimit = 25;
constexpr size_t kCandidatePoolLimit = 75;

struct LocalSettingsCache {
  std::wstring path;
  FILETIME last_write{};
  bool loaded = false;
  std::unordered_map<std::wstring, std::vector<std::wstring>> phrases;
  std::unordered_map<std::wstring, std::unordered_map<std::wstring, unsigned>> learning;

  int input_mode = 0;
  void Refresh() {
    const std::wstring current_path = SettingsPath();
    const int shared_input_mode = gy::input_mode::Read();
    WIN32_FILE_ATTRIBUTE_DATA attributes{};
    FILETIME current_write{};
    if (!current_path.empty() && GetFileAttributesExW(current_path.c_str(), GetFileExInfoStandard, &attributes)) {
      current_write = attributes.ftLastWriteTime;
    }
    if (loaded && current_path == path && CompareFileTime(&current_write, &last_write) == 0) {
      input_mode = shared_input_mode;
      return;
    }

    loaded = true;
    path = current_path;
    last_write = current_write;
    phrases.clear();
    learning.clear();
    input_mode = 0;
    if (path.empty()) return;
    input_mode = shared_input_mode;

    for (const std::wstring& line : ReadIniSection(path, L"Phrases")) {
      const size_t separator = line.find(L'=');
      if (separator == std::wstring::npos) continue;
      const std::wstring code = NormalizeCode(line.substr(0, separator));
      const std::wstring phrase_list = line.substr(separator + 1);
      if (code.empty()) continue;
      size_t begin = 0;
      while (begin <= phrase_list.size()) {
        const size_t end = phrase_list.find(L'|', begin);
        const std::wstring phrase = Trim(phrase_list.substr(begin,
            end == std::wstring::npos ? std::wstring::npos : end - begin));
        if (!phrase.empty()) phrases[code].push_back(phrase);
        if (end == std::wstring::npos) break;
        begin = end + 1;
      }
    }
    for (const std::wstring& line : ReadIniSection(path, L"Learning")) {
      const size_t equals = line.find(L'=');
      const size_t separator = line.find(L'\x2192');
      if (equals == std::wstring::npos || separator == std::wstring::npos || separator >= equals) continue;
      const std::wstring code = NormalizeCode(line.substr(0, separator));
      const std::wstring candidate = line.substr(separator + 1, equals - separator - 1);
      if (code.empty() || candidate.empty()) continue;
      try {
        learning[code][candidate] = std::min<unsigned>(static_cast<unsigned>(std::stoul(line.substr(equals + 1))), 100000u);
      } catch (...) {}
    }
  }

  void Invalidate() { loaded = false; }
};

LocalSettingsCache& SettingsCache() {
  static LocalSettingsCache cache;
  return cache;
}

std::unordered_map<std::wstring, unsigned> LearningScores(const std::wstring& code) {
  auto& cache = SettingsCache();
  cache.Refresh();
  const auto found = cache.learning.find(NormalizeCode(code));
  return found == cache.learning.end() ? std::unordered_map<std::wstring, unsigned>{} : found->second;
}

std::vector<std::wstring> LocalPhrases(const std::wstring& code) {
  auto& cache = SettingsCache();
  cache.Refresh();
  const auto found = cache.phrases.find(NormalizeCode(code));
  return found == cache.phrases.end() ? std::vector<std::wstring>{} : found->second;
}
struct Runtime {
  std::once_flag started;
  RimeApi* api = nullptr;
  bool ready = false;
  std::wstring diagnostic;
  std::mutex mutex;

  void Start(const std::wstring& module_directory) {
    std::call_once(started, [&] {
      const std::wstring shared = JoinPath(JoinPath(module_directory, L"rime-data"), L"shared");
      wchar_t local_app_data[MAX_PATH]{};
      if (!GetEnvironmentVariableW(L"LOCALAPPDATA", local_app_data, MAX_PATH)) {
        diagnostic = L"LOCALAPPDATA is unavailable";
        return;
      }
      const std::wstring gy_root = JoinPath(local_app_data, L"GYInput");
      const std::wstring user = JoinPath(gy_root, L"rime");
      if ((!CreateDirectoryW(gy_root.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) ||
          (!CreateDirectoryW(user.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS)) {
        diagnostic = L"cannot create the local Rime data directory";
        return;
      }
      if (GetFileAttributesW(JoinPath(shared, L"luna_pinyin.schema.yaml").c_str()) == INVALID_FILE_ATTRIBUTES) {
        diagnostic = L"the bundled luna_pinyin schema is missing";
        return;
      }
      const std::string shared_utf8 = Utf8(shared);
      const std::string user_utf8 = Utf8(user);
      RIME_STRUCT(RimeTraits, traits);
      traits.shared_data_dir = shared_utf8.c_str();
      traits.user_data_dir = user_utf8.c_str();
      traits.distribution_name = "GY Input Method";
      traits.distribution_code_name = "gyime";
      traits.distribution_version = GY_RELEASE_VERSION;
      traits.app_name = "rime.gyime";
      traits.min_log_level = 2;
      api = rime_get_api();
      if (!api) {
        diagnostic = L"rime_get_api returned null";
        return;
      }
      api->setup(&traits);
      // Rime caches the user build directory during initialize(). Refresh the
      // generated workspace before that point; otherwise maintenance can write
      // the already-cached five-candidate schema straight back to disk.
      if (!EnsureBundledWorkspace(shared, user)) {
        diagnostic = L"cannot deploy the bundled Rime workspace";
        return;
      }
      api->initialize(&traits);
      // Existing profiles retain their workspace. Maintenance still updates user
      // dictionaries and configuration without blocking the first usable session.
      if (api->start_maintenance(False)) api->join_maintenance_thread();
      ready = true;
    });
  }
};

Runtime& GetRuntime() {
  static Runtime runtime;
  return runtime;
}
}  // namespace

struct PinyinEngine::Impl {
  explicit Impl(std::wstring directory) : module_directory(std::move(directory)) {
    auto& runtime = GetRuntime();
    runtime.Start(module_directory);
    if (!runtime.ready) {
      diagnostic = runtime.diagnostic;
      return;
    }
    std::scoped_lock lock(runtime.mutex);
    session = runtime.api->create_session();
    if (!session) {
      diagnostic = L"librime could not create a session";
      return;
    }
    if (!runtime.api->select_schema(session, "gy_pinyin")) {
      runtime.api->destroy_session(session);
      session = 0;
      diagnostic = L"librime could not select gy_pinyin";
      return;
    }
    runtime.api->set_option(session, "ascii_mode", False);
    runtime.api->set_option(session, "zh_hans", True);
  }

  ~Impl() {
    auto& runtime = GetRuntime();
    if (session && runtime.ready) {
      std::scoped_lock lock(runtime.mutex);
      runtime.api->destroy_session(session);
    }
  }

  std::wstring module_directory;
  RimeSessionId session = 0;
  std::wstring diagnostic;
};

PinyinEngine::PinyinEngine(std::wstring module_directory) : impl_(std::make_unique<Impl>(std::move(module_directory))) {}
PinyinEngine::~PinyinEngine() = default;

bool PinyinEngine::IsReady() const {
  return impl_ && impl_->session != 0 && GetRuntime().ready;
}

std::wstring PinyinEngine::Diagnostic() const {
  return impl_ ? impl_->diagnostic : L"engine implementation is unavailable";
}

std::vector<std::wstring> PinyinEngine::Lookup(const std::wstring& pinyin) const {
  if (!IsReady() || pinyin.empty()) return {};
  auto& runtime = GetRuntime();
  auto& settings = SettingsCache();
  settings.Refresh();
  const int input_mode = settings.input_mode;
  if (input_mode == 2) return {};
  std::scoped_lock lock(runtime.mutex);
  runtime.api->clear_composition(impl_->session);
  runtime.api->set_option(impl_->session, "ascii_mode", False);
  const std::string keys = Utf8(pinyin);
  for (const unsigned char key : keys) {
    if (!runtime.api->process_key(impl_->session, key, 0)) return {};
  runtime.api->set_option(impl_->session, "zh_hans", input_mode == 0 ? True : False);
  }
  RIME_STRUCT(RimeContext, context);
  if (!runtime.api->get_context(impl_->session, &context)) return {};
  std::vector<std::wstring> candidates;
  std::vector<std::wstring> deep_candidates;
  const int raw_candidate_count = std::min(context.menu.num_candidates, kRawCandidateScanLimit);
  for (int i = 0; i < raw_candidate_count && candidates.size() + deep_candidates.size() < kCandidatePoolLimit; ++i) {
    const std::wstring candidate = NormalizeOutputScript(Wide(context.menu.candidates[i].text), input_mode);
    if (!IsCandidateAcceptable(candidate) ||
        std::find(candidates.begin(), candidates.end(), candidate) != candidates.end() ||
        std::find(deep_candidates.begin(), deep_candidates.end(), candidate) != deep_candidates.end()) {
      continue;
    }
    if (candidates.size() < kPrimaryCandidateLimit) {
      candidates.push_back(candidate);
    } else if (IsDeepCandidateAcceptable(candidate)) {
      deep_candidates.push_back(candidate);
    }
  }
  runtime.api->free_context(&context);
  candidates.insert(candidates.end(), deep_candidates.begin(), deep_candidates.end());
  const auto scores = LearningScores(pinyin);
  std::stable_sort(candidates.begin(), candidates.end(), [&scores](const std::wstring& left, const std::wstring& right) {
    const auto left_score = scores.contains(left) ? scores.at(left) : 0u;
    const auto right_score = scores.contains(right) ? scores.at(right) : 0u;
    return left_score > right_score;
  });
  const auto phrases = LocalPhrases(pinyin);
  for (auto it = phrases.rbegin(); it != phrases.rend(); ++it) {
    const std::wstring phrase = NormalizeOutputScript(*it, input_mode);
    if (!IsCandidateAcceptable(phrase)) continue;
    candidates.erase(std::remove(candidates.begin(), candidates.end(), phrase), candidates.end());
    candidates.insert(candidates.begin(), phrase);
  }
  candidates.erase(std::unique(candidates.begin(), candidates.end()), candidates.end());
  if (candidates.size() > kCandidatePoolLimit) candidates.resize(kCandidatePoolLimit);
  return candidates;
}

void PinyinEngine::Learn(const std::wstring& pinyin, const std::wstring& candidate) const {
  if (pinyin.empty() || candidate.empty()) return;
  const std::wstring path = SettingsPath();
  if (!EnsureUnicodeSettingsFile(path)) return;
  const std::wstring key = pinyin + L"→" + candidate;
  const unsigned previous = GetPrivateProfileIntW(L"Learning", key.c_str(), 0, path.c_str());
  const unsigned next = std::min<unsigned>(previous + 1, 100000u);
  WritePrivateProfileStringW(L"Learning", key.c_str(), std::to_wstring(next).c_str(), path.c_str());
  SettingsCache().Invalidate();
}
