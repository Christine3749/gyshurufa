#include "PinyinEngine.h"
#include "CandidateLayout.h"
#include "CandidatePoolPolicy.h"
#include "CorrectionPolicy.h"
#include "EnglishLexicon.h"
#include "EnglishCandidatePolicy.h"
#include "InputMode.h"
#include "SettingsFile.h"

#include <windows.h>

#include <rime_api.h>

#include <algorithm>
#include <array>
#include <cwctype>
#include <limits>
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

int ActiveInputMode() {
#if defined(GY_CANDIDATE_LAB)
  // The visual candidate laboratory is a separate executable.  Its mode
  // picker must never write to the user's live TSF/registry state, so the
  // laboratory has a process-local override.  Production binaries do not
  // compile this branch.
  wchar_t override_value[16]{};
  if (GetEnvironmentVariableW(L"GYINPUT_CANDIDATE_LAB_MODE", override_value,
                              static_cast<DWORD>(std::size(override_value)))) {
    if (override_value[0] >= L'0' && override_value[0] <= L'2' &&
        override_value[1] == L'\0') {
      return static_cast<int>(override_value[0] - L'0');
    }
  }
#endif
  return gy::input_mode::Read();
}

struct LearningStat {
  // `count` records only explicit candidate selection.  A plain Space / Enter
  // confirmation of the default item never reaches Learn(), so it can never
  // manufacture a personal preference.
  unsigned count = 0;
  std::uint64_t last_explicit_sequence = 0;
  std::uint64_t first_day = 0;
  std::uint64_t last_day = 0;
  unsigned active_days = 0;
  unsigned recent_7_days = 0;
  std::uint64_t recent_7_start_day = 0;
  unsigned recent_30_days = 0;
  std::uint64_t recent_30_start_day = 0;
  bool pinned = false;
};

std::vector<std::wstring> SplitFields(const std::wstring& value) {
  std::vector<std::wstring> fields;
  size_t begin = 0;
  while (begin <= value.size()) {
    const size_t end = value.find(L'|', begin);
    fields.push_back(value.substr(begin, end == std::wstring::npos ? std::wstring::npos : end - begin));
    if (end == std::wstring::npos) break;
    begin = end + 1;
  }
  return fields;
}

unsigned ParseUnsigned(const std::wstring& value) {
  try {
    return std::min<unsigned>(static_cast<unsigned>(std::stoul(value)), 100000u);
  } catch (...) {
    return 0;
  }
}

std::uint64_t ParseDay(const std::wstring& value) {
  try {
    return static_cast<std::uint64_t>(std::stoull(value));
  } catch (...) {
    return 0;
  }
}

LearningStat ParseLearningStat(const std::wstring& value) {
  const auto fields = SplitFields(value);
  LearningStat stat{};
  if (fields.size() < 9) return stat;
  stat.count = ParseUnsigned(fields[0]);
  // v1 had nine fields. v2 inserts an explicit-selection sequence after the
  // count. v1 records remain visible but cannot accidentally promote because
  // their sequence remains zero.
  const size_t offset = fields.size() >= 10 ? 1 : 0;
  if (offset) stat.last_explicit_sequence = ParseDay(fields[1]);
  stat.first_day = ParseDay(fields[1 + offset]);
  stat.last_day = ParseDay(fields[2 + offset]);
  stat.active_days = ParseUnsigned(fields[3 + offset]);
  stat.recent_7_days = ParseUnsigned(fields[4 + offset]);
  stat.recent_7_start_day = ParseDay(fields[5 + offset]);
  stat.recent_30_days = ParseUnsigned(fields[6 + offset]);
  stat.recent_30_start_day = ParseDay(fields[7 + offset]);
  stat.pinned = fields[8 + offset] == L"1";
  return stat;
}

std::wstring SerializeLearningStat(const LearningStat& stat) {
  return std::to_wstring(stat.count) + L"|" +
         std::to_wstring(stat.last_explicit_sequence) + L"|" +
         std::to_wstring(stat.first_day) + L"|" +
         std::to_wstring(stat.last_day) + L"|" +
         std::to_wstring(stat.active_days) + L"|" +
         std::to_wstring(stat.recent_7_days) + L"|" +
         std::to_wstring(stat.recent_7_start_day) + L"|" +
         std::to_wstring(stat.recent_30_days) + L"|" +
         std::to_wstring(stat.recent_30_start_day) + L"|" +
         (stat.pinned ? L"1" : L"0");
}

bool IsPromotionArmed(const LearningStat& stat) {
  return stat.last_explicit_sequence != 0 && stat.count >= 3;
}

PinyinEngine::LearningTier LearningTierFor(const LearningStat& stat) {
  if (stat.pinned) return PinyinEngine::LearningTier::Fixed;
  if (IsPromotionArmed(stat)) return PinyinEngine::LearningTier::Armed;
  if (stat.count > 0) return PinyinEngine::LearningTier::Observed;
  return PinyinEngine::LearningTier::None;
}

std::uint64_t LearningRankScore(const LearningStat& stat) {
  // The candidate that completed three explicit selections most recently
  // wins on the next lookup. This gives the user a stable, reversible rule:
  // a competing candidate needs its own three deliberate selections before
  // it can replace the existing first choice.
  if (stat.pinned) return std::numeric_limits<std::uint64_t>::max();
  return IsPromotionArmed(stat) ? stat.last_explicit_sequence : 0;
}

std::wstring ScopedLearningCode(const std::wstring& raw, int input_mode) {
  const std::wstring normalized = NormalizeCode(raw);
  if (normalized.empty()) return {};
  return (input_mode == gy::input_mode::kTraditional ? L"T:" : L"S:") + normalized;
}

std::wstring LegacyLearningCode(const std::wstring& raw) {
  const std::wstring normalized = NormalizeCode(raw);
  return normalized.empty() ? std::wstring{} : L"L:" + normalized;
}

std::wstring ParseStoredLearningCode(const std::wstring& raw) {
  if (raw.size() > 2 && (raw.rfind(L"S:", 0) == 0 || raw.rfind(L"T:", 0) == 0 ||
                         raw.rfind(L"L:", 0) == 0)) {
    const std::wstring normalized = NormalizeCode(raw.substr(2));
    return normalized.empty() ? std::wstring{} : raw.substr(0, 2) + normalized;
  }
  return LegacyLearningCode(raw);
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
  // Conversion output must not depend on the Windows display-language setting.
  // A user running an English UI still expects 繁体 mode to emit 繁體字.
  const wchar_t* locale = input_mode == 1 ? L"zh-Hant" : L"zh-Hans";
  const int length = LCMapStringEx(locale, flags, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr, 0);
  if (length <= 0) return value;
  std::wstring converted(static_cast<size_t>(length), L'\0');
  if (LCMapStringEx(locale, flags, value.data(), static_cast<int>(value.size()), converted.data(), length, nullptr, nullptr, 0) <= 0) return value;
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
  // Paging must not be locked by the quality bar: deep pages accept the same
  // candidates as the primary page (CJK ideographs, bounded length). Rime
  // still owns the ranking, so rare tail items stay at the tail but remain
  // reachable. Single-syllable queries (wo, yi, ...) only produce one-
  // character candidates; requiring size >= 2 here emptied every page after
  // the first and hard-locked paging at 25. Quality tuning may tighten this
  // later, but never by capping the pool again.
  return IsCandidateAcceptable(candidate);
}

// The candidate window remains a 5 × 5 page. Keep the user's exact pinyin
// results first. If that exact result set is too short to fill the first page,
// Lookup() appends de-duplicated candidates from progressively shorter valid
// pinyin prefixes (for example gei → ge). That is a real candidate fallback,
// not a UI placeholder: every filled slot is still selectable and commits its
// own Chinese text. Later pages retain the complete Rime-ranked pool.
constexpr int kRawCandidateScanLimit = static_cast<int>(gy::candidate_pool::MaximumSize());
constexpr size_t kFirstPageCandidateTarget = 25;
constexpr size_t kCandidatePoolLimit = gy::candidate_pool::MaximumSize();

struct LocalSettingsCache {
  std::wstring path;
  FILETIME last_write{};
  bool loaded = false;
  std::unordered_map<std::wstring, std::vector<std::wstring>> phrases;
  std::unordered_map<std::wstring, std::unordered_map<std::wstring, unsigned>> learning;
  std::unordered_map<std::wstring, std::unordered_map<std::wstring, LearningStat>> learning_stats;

  // Learn() runs on the host/UI path while TSF lookups read this cache from
  // application threads; every access below must hold this mutex.
  std::mutex mutex;
  void Refresh() {
    std::scoped_lock refresh_lock(mutex);
    const std::wstring current_path = SettingsPath();
    WIN32_FILE_ATTRIBUTE_DATA attributes{};
    FILETIME current_write{};
    if (!current_path.empty() && GetFileAttributesExW(current_path.c_str(), GetFileExInfoStandard, &attributes)) {
      current_write = attributes.ftLastWriteTime;
    }
    if (loaded && current_path == path && CompareFileTime(&current_write, &last_write) == 0) {
      return;
    }

    loaded = true;
    path = current_path;
    last_write = current_write;
    phrases.clear();
    learning.clear();
    learning_stats.clear();
    if (path.empty()) return;

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
      const std::wstring code = ParseStoredLearningCode(line.substr(0, separator));
      const std::wstring candidate = line.substr(separator + 1, equals - separator - 1);
      if (code.empty() || candidate.empty()) continue;
      try {
        learning[code][candidate] = std::min<unsigned>(static_cast<unsigned>(std::stoul(line.substr(equals + 1))), 100000u);
      } catch (...) {}
    }
    for (const std::wstring& line : ReadIniSection(path, L"LearningStats")) {
      const size_t equals = line.find(L'=');
      const size_t separator = line.find(L'\x2192');
      if (equals == std::wstring::npos || separator == std::wstring::npos || separator >= equals) continue;
      const std::wstring code = ParseStoredLearningCode(line.substr(0, separator));
      const std::wstring candidate = line.substr(separator + 1, equals - separator - 1);
      if (code.empty() || candidate.empty()) continue;
      learning_stats[code][candidate] = ParseLearningStat(line.substr(equals + 1));
    }
    // Older releases only wrote [Learning]. Keep those records as weak
    // candidates, but never let historical automatic confirmations become a
    // preferred top choice.
    for (const auto& [code, entries] : learning) {
      for (const auto& [candidate, count] : entries) {
        auto& stat = learning_stats[code][candidate];
        stat.count = std::max(stat.count, std::min(count, 1u));
      }
    }
  }

  void Invalidate() { std::scoped_lock lock(mutex); loaded = false; }
};

LocalSettingsCache& SettingsCache() {
  static LocalSettingsCache cache;
  return cache;
}

std::unordered_map<std::wstring, LearningStat> LearningStatistics(const std::wstring& raw_code,
                                                                   int input_mode) {
  auto& cache = SettingsCache();
  cache.Refresh();
  std::scoped_lock lock(cache.mutex);
  const std::wstring code = ScopedLearningCode(raw_code, input_mode);
  const auto scoped = cache.learning_stats.find(code);
  if (scoped != cache.learning_stats.end()) return scoped->second;
  const auto legacy = cache.learning_stats.find(LegacyLearningCode(raw_code));
  return legacy == cache.learning_stats.end() ? std::unordered_map<std::wstring, LearningStat>{} : legacy->second;
}

std::vector<std::wstring> LocalPhrases(const std::wstring& code) {
  auto& cache = SettingsCache();
  cache.Refresh();
  std::scoped_lock lock(cache.mutex);
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
    // This constructor runs in the out-of-process Host / health verifier, not
    // inside a target application's TSF key callback. Load the already
    // verified local English snapshot once so every later EN or mixed lookup
    // is an in-memory operation.
    gy::english_lexicon::RefreshVerifiedSnapshot();
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
    if (!runtime.api->select_schema(session, "luna_pinyin")) {
      runtime.api->destroy_session(session);
      session = 0;
      diagnostic = L"librime could not select luna_pinyin";
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

std::vector<std::wstring> PinyinEngine::LookupExact(const std::wstring& pinyin, int requested_mode) const {
  if (!IsReady() || pinyin.empty()) return {};
  if (requested_mode < gy::input_mode::kSimplified || requested_mode > gy::input_mode::kEnglish) return {};
  const int input_mode = requested_mode;
  if (gy::input_mode::IsEnglish(input_mode)) return {};
  auto& runtime = GetRuntime();
  auto& settings = SettingsCache();
  settings.Refresh();
  std::scoped_lock lock(runtime.mutex);
  const auto query_rime = [&](const std::wstring& code) {
    std::vector<std::wstring> result;
    runtime.api->clear_composition(impl_->session);
    runtime.api->set_option(impl_->session, "ascii_mode", False);
    // Set the script option before feeding keys: the very first keystroke must
    // already see the active 简/繁 mode, not whatever option a previous lookup
    // left on this shared session.
    runtime.api->set_option(impl_->session, "zh_hans", input_mode == 0 ? True : False);
    const std::string keys = Utf8(code);
    for (const unsigned char key : keys) {
      if (!runtime.api->process_key(impl_->session, key, 0)) return result;
    }
    RIME_STRUCT(RimeContext, context);
    if (!runtime.api->get_context(impl_->session, &context)) return result;
    const int raw_candidate_count = std::min(context.menu.num_candidates, kRawCandidateScanLimit);
    for (int i = 0; i < raw_candidate_count && result.size() < kCandidatePoolLimit; ++i) {
      const std::wstring candidate = NormalizeOutputScript(Wide(context.menu.candidates[i].text), input_mode);
      if (!IsCandidateAcceptable(candidate) ||
          std::find(result.begin(), result.end(), candidate) != result.end()) {
        continue;
      }
      result.push_back(candidate);
    }
    runtime.api->free_context(&context);
    return result;
  };

  std::vector<std::wstring> candidates = query_rime(pinyin);
  // User phrases are a first-class local dictionary. A short alias such as
  // "dz=地址" is useful precisely because it need not be valid standard
  // pinyin, so do not require librime to produce a base candidate first.
  const auto phrases = LocalPhrases(pinyin);
  if (candidates.empty() && phrases.empty()) return {};
  const auto statistics = LearningStatistics(pinyin, input_mode);
  std::vector<std::wstring> weak_learned;
  // Learning must surface words, not merely reorder the bounded pool. Until
  // three explicit selections complete, a learned word remains weak and can
  // never displace the dictionary's first choice.
  for (const auto& entry : statistics) {
    const std::wstring learned = NormalizeOutputScript(entry.first, input_mode);
    if (!IsCandidateAcceptable(learned)) continue;
    if (std::find(candidates.begin(), candidates.end(), learned) != candidates.end()) continue;
    if (LearningRankScore(entry.second) == 0) {
      weak_learned.push_back(learned);
      continue;
    }
    candidates.push_back(learned);
  }
  std::stable_sort(candidates.begin(), candidates.end(), [&statistics](const std::wstring& left, const std::wstring& right) {
    const auto left_score = statistics.contains(left) ? LearningRankScore(statistics.at(left)) : 0ull;
    const auto right_score = statistics.contains(right) ? LearningRankScore(statistics.at(right)) : 0ull;
    return left_score > right_score;
  });
  const size_t weak_insert_position = std::min<size_t>(5, candidates.size());
  candidates.insert(candidates.begin() + static_cast<std::ptrdiff_t>(weak_insert_position),
                    weak_learned.begin(), weak_learned.end());
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

std::vector<std::wstring> PinyinEngine::Lookup(const std::wstring& pinyin, int requested_mode) const {
  if (requested_mode < gy::input_mode::kSimplified || requested_mode > gy::input_mode::kEnglish) return {};
  const int input_mode = requested_mode;
  const std::wstring normalized = NormalizeCode(pinyin);
  // EN is a candidate input method, not direct keyboard pass-through. Its
  // results are resolved exclusively from the local verified English snapshot.
  if (gy::input_mode::IsEnglish(input_mode)) {
    return gy::english_lexicon::PrefixMatches(
        normalized, gy::english_candidates::kExpandedVisible);
  }
  std::vector<std::wstring> candidates = LookupExact(pinyin, input_mode);

  // Mixed CN/EN is candidate policy, not a second online input path. A
  // verified local English word owns slot 1; normal Chinese choices remain
  // available behind it. Pure pinyin therefore keeps Chinese-first behavior.
  const std::wstring english = gy::english_lexicon::ExactWord(normalized);
  if (!english.empty()) {
    candidates.erase(std::remove(candidates.begin(), candidates.end(), english), candidates.end());
    candidates.insert(candidates.begin(), english);
  } else {
    std::size_t prefix_length = 0;
    const std::wstring suffix = gy::english_lexicon::SuffixWord(normalized, &prefix_length);
    if (!suffix.empty() && prefix_length >= 2 && prefix_length < normalized.size()) {
      const auto prefix_candidates = LookupExact(normalized.substr(0, prefix_length), input_mode);
      const auto first_chinese = std::find_if(prefix_candidates.begin(), prefix_candidates.end(),
                                              [](const std::wstring& candidate) {
                                                return IsCandidateAcceptable(candidate);
                                              });
      if (first_chinese != prefix_candidates.end()) {
        const std::wstring mixed = *first_chinese + L" " + suffix;
        candidates.erase(std::remove(candidates.begin(), candidates.end(), mixed), candidates.end());
        candidates.insert(candidates.begin(), mixed);
      }
    }
  }
  // A narrowly-defined spelling correction may borrow normal candidates from
  // its conservative pinyin base. The actual correction is inserted later by
  // the UI as a red #2–4 suggestion, never here as an automatic first choice.
  if (candidates.empty()) {
    const std::wstring correction_fallback = gy::correction::PinyinSpellingFallback(normalized);
    if (!correction_fallback.empty()) candidates = LookupExact(correction_fallback, input_mode);
  }
  if (candidates.empty()) return {};

  // Exact input always owns the front of the list. Only when it cannot fill
  // the 5 × 5 first page do we add shorter, valid pinyin prefixes behind it:
  // gei → ge, nihao → niha → nih … . A prefix is queried rather than guessed;
  // if Rime has no real candidates for it, it contributes nothing. Do not go
  // below two letters: a bare initial is too noisy and is not a usable pinyin
  // fallback surface.
  std::wstring fallback = NormalizeCode(pinyin);
  while (candidates.size() < kFirstPageCandidateTarget && fallback.size() > 2) {
    fallback.pop_back();
    while (!fallback.empty() && fallback.back() == L'\'') fallback.pop_back();
    if (fallback.size() < 2) break;
    const auto fallback_candidates = LookupExact(fallback, input_mode);
    for (const std::wstring& candidate : fallback_candidates) {
      if (std::find(candidates.begin(), candidates.end(), candidate) != candidates.end()) continue;
      candidates.push_back(candidate);
      if (candidates.size() >= kFirstPageCandidateTarget) break;
    }
  }
  if (candidates.size() > kCandidatePoolLimit) candidates.resize(kCandidatePoolLimit);
  return candidates;
}

void PinyinEngine::Learn(const std::wstring& pinyin, const std::wstring& candidate, int requested_mode) const {
  if (pinyin.empty() || candidate.empty()) return;
  const std::wstring path = SettingsPath();
  if (!EnsureUnicodeSettingsFile(path)) return;
  const int input_mode = requested_mode >= gy::input_mode::kSimplified &&
      requested_mode <= gy::input_mode::kTraditional ? requested_mode : ActiveInputMode();
  if (gy::input_mode::IsEnglish(input_mode)) return;
  const std::wstring code = ScopedLearningCode(pinyin, input_mode);
  if (code.empty()) return;
  const std::wstring key = code + L"→" + candidate;
  LearningStat stat{};
  std::uint64_t next_sequence = 1;
  {
    auto& cache = SettingsCache();
    cache.Refresh();
    std::scoped_lock lock(cache.mutex);
    const auto code_stats = cache.learning_stats.find(code);
    if (code_stats != cache.learning_stats.end()) {
      for (const auto& [_, existing] : code_stats->second) {
        next_sequence = std::max(next_sequence, existing.last_explicit_sequence + 1);
      }
      const auto entry = code_stats->second.find(candidate);
      if (entry != code_stats->second.end()) stat = entry->second;
    }
  }
  // An imported v1 record has no explicit-selection sequence. Treat it as at
  // most two observations so the next real user choice becomes an honest
  // third confirmation rather than silently inheriting historic frequency.
  if (stat.last_explicit_sequence == 0 && stat.count > 2) stat.count = 2;
  stat.count = std::min<unsigned>(stat.count + 1, 100000u);
  // The sequence freezes when the candidate reaches exactly three explicit
  // selections. Further clicks cannot silently reclaim priority from a newer
  // three-selection competitor.
  if (stat.count == 3) stat.last_explicit_sequence = next_sequence;

  const bool legacy_ok = WritePrivateProfileStringW(L"Learning", key.c_str(),
                                                      std::to_wstring(stat.count).c_str(), path.c_str()) != FALSE;
  const bool stats_ok = WritePrivateProfileStringW(L"LearningStats", key.c_str(),
                                                     SerializeLearningStat(stat).c_str(), path.c_str()) != FALSE;
  SettingsCache().Invalidate();
  (void)legacy_ok;
  (void)stats_ok;
}

void PinyinEngine::UndoLastLearn(const std::wstring& pinyin, const std::wstring& candidate,
                                 int requested_mode) const {
  if (pinyin.empty() || candidate.empty()) return;
  const std::wstring path = SettingsPath();
  if (!EnsureUnicodeSettingsFile(path)) return;
  const int input_mode = requested_mode >= gy::input_mode::kSimplified &&
      requested_mode <= gy::input_mode::kTraditional ? requested_mode : ActiveInputMode();
  if (gy::input_mode::IsEnglish(input_mode)) return;
  const std::wstring code = ScopedLearningCode(pinyin, input_mode);
  if (code.empty()) return;
  const std::wstring key = code + L"→" + candidate;
  LearningStat stat{};
  bool found = false;
  {
    auto& cache = SettingsCache();
    cache.Refresh();
    std::scoped_lock lock(cache.mutex);
    const auto code_stats = cache.learning_stats.find(code);
    if (code_stats != cache.learning_stats.end()) {
      const auto entry = code_stats->second.find(candidate);
      if (entry != code_stats->second.end()) {
        stat = entry->second;
        found = true;
      }
    }
  }
  if (!found || stat.count == 0) return;
  --stat.count;
  if (stat.count < 3) stat.last_explicit_sequence = 0;
  const bool legacy_ok = WritePrivateProfileStringW(L"Learning", key.c_str(),
      std::to_wstring(stat.count).c_str(), path.c_str()) != FALSE;
  const bool stats_ok = WritePrivateProfileStringW(L"LearningStats", key.c_str(),
      SerializeLearningStat(stat).c_str(), path.c_str()) != FALSE;
  SettingsCache().Invalidate();
  (void)legacy_ok;
  (void)stats_ok;
}

bool PinyinEngine::SetLearningPinned(const std::wstring& pinyin, const std::wstring& candidate, bool pinned) const {
  if (pinyin.empty() || candidate.empty()) return false;
  const std::wstring path = SettingsPath();
  if (!EnsureUnicodeSettingsFile(path)) return false;
  const int input_mode = ActiveInputMode();
  if (gy::input_mode::IsEnglish(input_mode)) return false;
  const std::wstring code = ScopedLearningCode(pinyin, input_mode);
  if (code.empty()) return false;
  const std::wstring key = code + L"→" + candidate;
  LearningStat stat{};
  {
    auto& cache = SettingsCache();
    cache.Refresh();
    std::scoped_lock lock(cache.mutex);
    const auto code_stats = cache.learning_stats.find(code);
    if (code_stats != cache.learning_stats.end()) {
      const auto entry = code_stats->second.find(candidate);
      if (entry != code_stats->second.end()) stat = entry->second;
    }
  }
  stat.pinned = pinned;
  const bool ok = WritePrivateProfileStringW(L"LearningStats", key.c_str(),
                                              SerializeLearningStat(stat).c_str(), path.c_str()) != FALSE;
  SettingsCache().Invalidate();
  return ok;
}

PinyinEngine::LearningSummary PinyinEngine::GetLearningSummary(const std::wstring& pinyin,
                                                               const std::wstring& candidate) const {
  LearningSummary summary{};
  if (pinyin.empty() || candidate.empty()) return summary;
  auto& cache = SettingsCache();
  cache.Refresh();
  std::scoped_lock lock(cache.mutex);
  const int input_mode = ActiveInputMode();
  if (gy::input_mode::IsEnglish(input_mode)) return summary;
  const std::wstring code = ScopedLearningCode(pinyin, input_mode);
  if (code.empty()) return summary;
  LearningStat stat{};
  bool found = false;
  const auto code_stats = cache.learning_stats.find(code);
  if (code_stats != cache.learning_stats.end()) {
    const auto entry = code_stats->second.find(candidate);
    if (entry != code_stats->second.end()) {
      stat = entry->second;
      found = true;
    }
  }
  if (!found) return summary;
  summary.count = stat.count;
  summary.recent_7_days = stat.recent_7_days;
  summary.recent_30_days = stat.recent_30_days;
  summary.active_days = stat.active_days;
  summary.pinned = stat.pinned;
  summary.armed = IsPromotionArmed(stat);
  summary.tier = LearningTierFor(stat);
  return summary;
}
