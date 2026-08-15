#include "EnglishLexicon.h"

#include "InputMode.h"

#include <windows.h>
#include <wincrypt.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

namespace gy::english_lexicon {
namespace {

constexpr std::size_t kMinimumWordLength = 3;
constexpr std::size_t kMaximumWordLength = 64;
constexpr std::size_t kMaximumSnapshotBytes = 16u * 1024u * 1024u;
constexpr std::size_t kMaximumSnapshotWords = 250000;
constexpr ULONGLONG kSnapshotProbeIntervalMs = 2000;
constexpr wchar_t kBundledLexiconRelativePath[] = L"\\english-lexicon\\english.tsv";

// This bootstrap pins the most important product words at the front. A fresh
// install also ships a larger frequency-ranked baseline, while a verified
// downloaded snapshot can add later publisher updates without entering the
// typing path.
constexpr std::array<std::wstring_view, 70> kBootstrapWords{
    L"about", L"account", L"agent", L"api", L"app", L"blue", L"browser", L"build",
    L"candidate", L"chatgpt", L"cloudflare", L"code", L"design", L"dictionary", L"download",
    L"email", L"english", L"file", L"github", L"hello", L"host", L"input", L"keyboard",
    L"lexicon", L"like", L"liked", L"likelihood", L"likely", L"likeness", L"likewise", L"link", L"login", L"message", L"mixed", L"model", L"network",
    L"note", L"offline", L"openai", L"page", L"password", L"pipeline", L"privacy", L"project",
    L"prompt", L"release", L"safe", L"service", L"settings", L"sync", L"system", L"terminal",
    L"test", L"update", L"version", L"website", L"windows",
    L"word", L"work", L"world", L"would", L"woman", L"worker", L"blueprint", L"blues", L"bluest"};

std::wstring LocalGyRoot() {
  wchar_t local_app_data[MAX_PATH]{};
  const DWORD length = GetEnvironmentVariableW(L"LOCALAPPDATA", local_app_data,
                                               static_cast<DWORD>(std::size(local_app_data)));
  if (length == 0 || length >= std::size(local_app_data)) return {};
  return std::wstring(local_app_data, length) + L"\\GYInput";
}

std::wstring ModuleDirectory() {
  std::vector<wchar_t> path(512);
  while (true) {
    const DWORD length = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
    if (length == 0) return {};
    if (length < path.size()) {
      std::wstring module(path.data(), length);
      const std::size_t separator = module.find_last_of(L"\\/");
      return separator == std::wstring::npos ? std::wstring{} : module.substr(0, separator);
    }
    if (path.size() >= 32768) return {};
    path.resize(path.size() * 2);
  }
}

std::wstring NormalizeWord(std::wstring_view value) {
  if (value.size() < kMinimumWordLength || value.size() > kMaximumWordLength) return {};
  std::wstring result;
  result.reserve(value.size());
  for (const wchar_t character : value) {
    if (character >= L'A' && character <= L'Z') {
      result.push_back(static_cast<wchar_t>(character - L'A' + L'a'));
    } else if ((character >= L'a' && character <= L'z') ||
               (character >= L'0' && character <= L'9') || character == L'+' ||
               character == L'.' || character == L'_' || character == L'-' ||
               character == L'\'') {
      result.push_back(character);
    } else {
      return {};
    }
  }
  if (result.empty() || result.front() < L'a' || result.front() > L'z') return {};
  return result;
}

std::wstring NormalizePrefix(std::wstring_view value) {
  if (value.empty() || value.size() > kMaximumWordLength) return {};
  std::wstring result;
  result.reserve(value.size());
  for (const wchar_t character : value) {
    if (character >= L'A' && character <= L'Z') {
      result.push_back(static_cast<wchar_t>(character - L'A' + L'a'));
    } else if ((character >= L'a' && character <= L'z') ||
               (character >= L'0' && character <= L'9') || character == L'+' ||
               character == L'.' || character == L'_' || character == L'-' ||
               character == L'\'') {
      result.push_back(character);
    } else {
      return {};
    }
  }
  return result.empty() || result.front() < L'a' || result.front() > L'z' ? std::wstring{} : result;
}

bool IsSafeVersion(std::wstring_view version) {
  if (version.size() < 10 || version.size() > 32) return false;
  for (const wchar_t character : version) {
    if ((character < L'0' || character > L'9') && character != L'.') return false;
  }
  return std::count(version.begin(), version.end(), L'.') >= 3;
}

bool ReadUtf8File(const std::wstring& path, std::size_t maximum_bytes, std::wstring* value) {
  if (!value) return false;
  value->clear();
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  LARGE_INTEGER size{};
  if (!GetFileSizeEx(file, &size) || size.QuadPart <= 0 ||
      static_cast<std::uint64_t>(size.QuadPart) > maximum_bytes) {
    CloseHandle(file);
    return false;
  }
  std::vector<char> bytes(static_cast<std::size_t>(size.QuadPart));
  DWORD read = 0;
  const bool read_ok = ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr) &&
                       read == bytes.size();
  CloseHandle(file);
  if (!read_ok) return false;
  const int wide_length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, bytes.data(),
                                               static_cast<int>(bytes.size()), nullptr, 0);
  if (wide_length <= 0) return false;
  value->resize(static_cast<std::size_t>(wide_length));
  return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, bytes.data(),
                             static_cast<int>(bytes.size()), value->data(), wide_length) == wide_length;
}

std::wstring ReadIniValue(const std::wstring& content, std::wstring_view name) {
  const std::wstring prefix = std::wstring(name) + L"=";
  std::size_t begin = 0;
  while (begin < content.size()) {
    const std::size_t end = content.find_first_of(L"\r\n", begin);
    const std::wstring_view line(content.data() + begin,
                                 (end == std::wstring::npos ? content.size() : end) - begin);
    if (line.size() >= prefix.size() && line.substr(0, prefix.size()) == prefix) {
      return std::wstring(line.substr(prefix.size()));
    }
    if (end == std::wstring::npos) break;
    begin = content.find_first_not_of(L"\r\n", end);
    if (begin == std::wstring::npos) break;
  }
  return {};
}

bool IsHexSha256(std::wstring_view value) {
  if (value.size() != 64) return false;
  return std::all_of(value.begin(), value.end(), [](wchar_t character) {
    return (character >= L'0' && character <= L'9') ||
           (character >= L'a' && character <= L'f') ||
           (character >= L'A' && character <= L'F');
  });
}

bool FileMatchesSha256(const std::wstring& path, std::wstring_view expected_hash) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  LARGE_INTEGER size{};
  HCRYPTPROV provider = 0;
  HCRYPTHASH hash = 0;
  bool success = GetFileSizeEx(file, &size) && size.QuadPart > 0 &&
      static_cast<std::uint64_t>(size.QuadPart) <= kMaximumSnapshotBytes &&
      CryptAcquireContextW(&provider, nullptr, nullptr, PROV_RSA_AES, CRYPT_VERIFYCONTEXT) &&
      CryptCreateHash(provider, CALG_SHA_256, 0, 0, &hash);
  std::array<BYTE, 8192> buffer{};
  while (success) {
    DWORD read = 0;
    if (!ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr)) {
      success = false;
      break;
    }
    if (read == 0) break;
    if (!CryptHashData(hash, buffer.data(), read, 0)) {
      success = false;
      break;
    }
  }
  std::array<BYTE, 32> digest{};
  DWORD digest_size = static_cast<DWORD>(digest.size());
  success = success && CryptGetHashParam(hash, HP_HASHVAL, digest.data(), &digest_size, 0) &&
      digest_size == digest.size();
  if (hash) CryptDestroyHash(hash);
  if (provider) CryptReleaseContext(provider, 0);
  CloseHandle(file);
  if (!success) return false;
  constexpr wchar_t kHex[] = L"0123456789ABCDEF";
  std::wstring actual;
  actual.reserve(digest.size() * 2);
  for (const BYTE byte : digest) {
    actual.push_back(kHex[(byte >> 4) & 0x0F]);
    actual.push_back(kHex[byte & 0x0F]);
  }
  return actual == expected_hash;
}

bool ParseStrictCount(std::wstring_view value, std::size_t* count) {
  if (!count || value.empty() || value.size() > 8) return false;
  std::size_t parsed = 0;
  for (const wchar_t character : value) {
    if (character < L'0' || character > L'9') return false;
    parsed = parsed * 10 + static_cast<std::size_t>(character - L'0');
    if (parsed > kMaximumSnapshotWords) return false;
  }
  if (parsed == 0) return false;
  *count = parsed;
  return true;
}

bool AppendLexiconBody(std::wstring_view body, std::unordered_set<std::wstring>* words,
                       std::vector<std::wstring>* ordered_words,
                       std::size_t* appended_count = nullptr) {
  if (!words || !ordered_words) return false;
  std::size_t count = 0;
  std::size_t begin = 0;
  while (begin < body.size()) {
    const std::size_t end = body.find_first_of(L"\r\n", begin);
    const std::wstring_view line(body.data() + begin,
                                 (end == std::wstring::npos ? body.size() : end) - begin);
    if (!line.empty()) {
      const std::wstring word = NormalizeWord(line);
      if (word.empty() || words->size() >= kMaximumSnapshotWords) return false;
      if (words->emplace(word).second) ordered_words->push_back(word);
      ++count;
    }
    if (end == std::wstring::npos) break;
    begin = body.find_first_not_of(L"\r\n", end);
    if (begin == std::wstring::npos) break;
  }
  if (appended_count) *appended_count = count;
  return count > 0;
}

struct SnapshotCache {
  std::mutex mutex;
  bool initialized = false;
  bool mixed_input_enabled = false;
  ULONGLONG next_probe_tick = 0;
  FILETIME state_last_write{};
  FILETIME settings_last_write{};
  std::wstring settings_path;
  std::unordered_set<std::wstring> words;
  std::vector<std::wstring> ordered_words;
};

SnapshotCache& Cache() {
  static SnapshotCache cache;
  return cache;
}

void ResetToBootstrap(SnapshotCache* cache) {
  if (!cache) return;
  cache->words.clear();
  cache->ordered_words.clear();
  for (const std::wstring_view word : kBootstrapWords) {
    if (cache->words.emplace(word).second) cache->ordered_words.emplace_back(word);
  }
}

bool LoadBundledLexicon(SnapshotCache* cache) {
  if (!cache) return false;
  const std::wstring module_directory = ModuleDirectory();
  if (module_directory.empty()) return false;
  std::wstring body;
  if (!ReadUtf8File(module_directory + kBundledLexiconRelativePath,
                    kMaximumSnapshotBytes, &body)) return false;
  return AppendLexiconBody(body, &cache->words, &cache->ordered_words);
}

bool LoadVerifiedSnapshot(SnapshotCache* cache, const std::wstring& root) {
  if (!cache || root.empty()) return false;
  std::wstring state;
  const std::wstring state_path = root + L"\\lexicons\\english-mixed\\english-mixed-state.ini";
  if (!ReadUtf8File(state_path, 4096, &state)) return false;
  const std::wstring version = ReadIniValue(state, L"activeVersion");
  const std::wstring status = ReadIniValue(state, L"status");
  const std::wstring sha256 = ReadIniValue(state, L"sha256");
  std::size_t expected_count = 0;
  if (status != L"ready" || !IsSafeVersion(version) || !IsHexSha256(sha256) ||
      !ParseStrictCount(ReadIniValue(state, L"entryCount"), &expected_count)) {
    return false;
  }
  std::wstring body;
  const std::wstring snapshot_path = root + L"\\lexicons\\english-mixed\\versions\\" + version + L"\\english.tsv";
  if (!FileMatchesSha256(snapshot_path, sha256) ||
      !ReadUtf8File(snapshot_path, kMaximumSnapshotBytes, &body)) return false;
  std::unordered_set<std::wstring> snapshot_words;
  std::vector<std::wstring> snapshot_ordered_words;
  std::size_t parsed_count = 0;
  if (!AppendLexiconBody(body, &snapshot_words, &snapshot_ordered_words, &parsed_count) ||
      parsed_count != expected_count || snapshot_words.size() != expected_count) return false;
  for (const std::wstring& word : snapshot_ordered_words) {
    if (cache->words.emplace(word).second) cache->ordered_words.push_back(word);
  }
  return true;
}

void RefreshSnapshot() {
  SnapshotCache& cache = Cache();
  std::scoped_lock lock(cache.mutex);
  const ULONGLONG now = GetTickCount64();
  if (cache.initialized && now < cache.next_probe_tick) return;
  cache.next_probe_tick = now + kSnapshotProbeIntervalMs;
  const std::wstring root = LocalGyRoot();
  const std::wstring state_path = root.empty() ? std::wstring{} :
      root + L"\\lexicons\\english-mixed\\english-mixed-state.ini";
  WIN32_FILE_ATTRIBUTE_DATA attributes{};
  FILETIME current_write{};
  if (!state_path.empty() && GetFileAttributesExW(state_path.c_str(), GetFileExInfoStandard, &attributes)) {
    current_write = attributes.ftLastWriteTime;
  }
  const std::wstring settings_path = gy::input_mode::SettingsPath();
  WIN32_FILE_ATTRIBUTE_DATA settings_attributes{};
  FILETIME settings_write{};
  if (!settings_path.empty() && GetFileAttributesExW(settings_path.c_str(), GetFileExInfoStandard,
                                                      &settings_attributes)) {
    settings_write = settings_attributes.ftLastWriteTime;
  }
  const bool snapshot_changed = !cache.initialized ||
      CompareFileTime(&cache.state_last_write, &current_write) != 0;
  const bool setting_changed = !cache.initialized || cache.settings_path != settings_path ||
      CompareFileTime(&cache.settings_last_write, &settings_write) != 0;
  if (!snapshot_changed && !setting_changed) return;
  cache.initialized = true;
  cache.state_last_write = current_write;
  cache.settings_path = settings_path;
  cache.settings_last_write = settings_write;
  if (setting_changed) {
    cache.mixed_input_enabled = !settings_path.empty() &&
        GetPrivateProfileIntW(L"MixedInput", L"Enabled", 0, settings_path.c_str()) != 0;
  }
  if (snapshot_changed) {
    ResetToBootstrap(&cache);
    LoadBundledLexicon(&cache);
    LoadVerifiedSnapshot(&cache, root);
  }
}

bool ContainsVerifiedWord(std::wstring_view raw) {
  const std::wstring normalized = NormalizeWord(raw);
  if (normalized.empty()) return false;
  SnapshotCache& cache = Cache();
  std::scoped_lock lock(cache.mutex);
  return cache.words.contains(normalized);
}

}  // namespace

void RefreshVerifiedSnapshot() {
  RefreshSnapshot();
}

bool IsMixedInputEnabled() {
  SnapshotCache& cache = Cache();
  std::scoped_lock lock(cache.mutex);
  return cache.mixed_input_enabled;
}

std::wstring ExactWord(std::wstring_view composition) {
  if (!IsMixedInputEnabled()) return {};
  const std::wstring normalized = NormalizeWord(composition);
  return !normalized.empty() && ContainsVerifiedWord(normalized) ? normalized : std::wstring{};
}

std::wstring SuffixWord(std::wstring_view composition, std::size_t* pinyin_prefix_length) {
  if (pinyin_prefix_length) *pinyin_prefix_length = 0;
  if (!IsMixedInputEnabled() || composition.size() < kMinimumWordLength + 2) return {};
  for (std::size_t begin = 2; begin + kMinimumWordLength <= composition.size(); ++begin) {
    const std::wstring suffix = ExactWord(composition.substr(begin));
    if (!suffix.empty()) {
      if (pinyin_prefix_length) *pinyin_prefix_length = begin;
      return suffix;
    }
  }
  return {};
}

std::vector<std::wstring> PrefixMatches(std::wstring_view composition, std::size_t maximum_results) {
  const std::wstring prefix = NormalizePrefix(composition);
  if (prefix.empty() || maximum_results == 0) return {};
  SnapshotCache& cache = Cache();
  std::scoped_lock lock(cache.mutex);
  std::vector<std::wstring> result;
  result.reserve(std::min<std::size_t>(maximum_results, 16));
  // A complete word is the most intentional result, even when a downloaded
  // list uses a different frequency order. Every remaining match preserves
  // the verified snapshot's ordering, which is the publisher's rank.
  if (cache.words.contains(prefix)) result.push_back(prefix);
  for (const std::wstring& word : cache.ordered_words) {
    if (word == prefix || word.size() < prefix.size() ||
        word.compare(0, prefix.size(), prefix) != 0) continue;
    result.push_back(word);
    if (result.size() >= maximum_results) break;
  }
  // Completing an already-valid word must still feel like an English input
  // method, not a dead-end candidate panel.  Add a few same-stem local words
  // only after exact and full-prefix matches, so `word` offers word/work/world
  // while a short prefix such as `wo` remains purely prefix ranked.
  if (cache.words.contains(prefix) && result.size() < std::min<std::size_t>(maximum_results, 5) &&
      prefix.size() >= 2) {
    const std::wstring stem = prefix.substr(0, 2);
    for (const std::wstring& word : cache.ordered_words) {
      if (word.size() < stem.size() || word.compare(0, stem.size(), stem) != 0 ||
          std::find(result.begin(), result.end(), word) != result.end()) continue;
      result.push_back(word);
      if (result.size() >= std::min<std::size_t>(maximum_results, 5)) break;
    }
  }
  return result;
}

}  // namespace gy::english_lexicon
