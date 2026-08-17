#include <windows.h>

#include <algorithm>
#include <iostream>
#include <string>

#include "InputMode.h"
#include "PinyinEngine.h"
#include "CorrectionPolicy.h"
#include "EnglishCandidatePolicy.h"

namespace {
std::wstring g_local_app_data;

std::wstring ModuleDirectory() {
  wchar_t path[MAX_PATH]{};
  const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (!length || length == MAX_PATH) return {};
  std::wstring directory(path, length);
  directory.resize(directory.find_last_of(L"\\/"));
  return directory;
}

bool UseIsolatedLocalAppData() {
  wchar_t temp[MAX_PATH]{};
  const DWORD length = GetTempPathW(MAX_PATH, temp);
  if (!length || length >= MAX_PATH) return false;
  const std::wstring directory = std::wstring(temp) + L"GYInput-PinyinSmoke-" +
      std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64());
  if (!CreateDirectoryW(directory.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) return false;
  if (!SetEnvironmentVariableW(L"LOCALAPPDATA", directory.c_str())) return false;
  g_local_app_data = directory;
  return true;
}

bool EnsureDirectory(const std::wstring& path) {
  return CreateDirectoryW(path.c_str(), nullptr) || GetLastError() == ERROR_ALREADY_EXISTS;
}

bool WriteAsciiFile(const std::wstring& path, const char* value) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  const DWORD expected = static_cast<DWORD>(lstrlenA(value));
  DWORD written = 0;
  const bool ok = WriteFile(file, value, expected, &written, nullptr) && written == expected;
  CloseHandle(file);
  return ok;
}

bool FileContainsAscii(const std::wstring& path, const char* needle) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  const DWORD size = GetFileSize(file, nullptr);
  if (size == INVALID_FILE_SIZE || size > 1024 * 1024) {
    CloseHandle(file);
    return false;
  }
  std::string content(size, '\0');
  DWORD read = 0;
  const bool ok = ReadFile(file, content.data(), size, &read, nullptr) && read == size;
  CloseHandle(file);
  return ok && content.find(needle) != std::string::npos;
}

bool SeedStaleGeneratedSchema() {
  const std::wstring gy_root = g_local_app_data + L"\\GYInput";
  const std::wstring rime_root = gy_root + L"\\rime";
  const std::wstring build_root = rime_root + L"\\build";
  if (!EnsureDirectory(gy_root) || !EnsureDirectory(rime_root) || !EnsureDirectory(build_root)) return false;
  return WriteAsciiFile(build_root + L"\\luna_pinyin.schema.yaml", "schema:\n  page_size: 5\n");
}

bool SeedVerifiedEnglishLexicon() {
  const std::wstring gy_root = g_local_app_data + L"\\GYInput";
  const std::wstring lexicon_root = gy_root + L"\\lexicons";
  const std::wstring english_root = lexicon_root + L"\\english-mixed";
  const std::wstring versions_root = english_root + L"\\versions";
  const std::wstring version_root = versions_root + L"\\2026.08.12.1";
  if (!EnsureDirectory(gy_root) || !EnsureDirectory(lexicon_root) || !EnsureDirectory(english_root) ||
      !EnsureDirectory(versions_root) || !EnsureDirectory(version_root)) return false;
  return WriteAsciiFile(version_root + L"\\english.tsv", "blue\nlike\n") &&
      WriteAsciiFile(english_root + L"\\english-mixed-state.ini",
          "schemaVersion=1\nstatus=ready\nactiveVersion=2026.08.12.1\n"
          "sha256=B019F167DA5B4BE72C38AD3E354942DBA9C33F99ED8EB8FD28378740B9FAE7CC\nentryCount=2\n");
}

bool IsCjkIdeograph(wchar_t character) {
  return (character >= 0x3400 && character <= 0x4DBF) ||
         (character >= 0x4E00 && character <= 0x9FFF) ||
         (character >= 0xF900 && character <= 0xFAFF);
}

bool UsesOnlyHanCharacters(const std::vector<std::wstring>& candidates) {
  for (const std::wstring& candidate : candidates) {
    if (candidate.empty()) return false;
    for (const wchar_t character : candidate) {
      if (!IsCjkIdeograph(character)) return false;
    }
  }
  return true;
}

class ScopedInputMode final {
public:
  explicit ScopedInputMode(int mode) : previous_(gy::input_mode::Read()) {
    gy::input_mode::Write(mode);
  }

  ~ScopedInputMode() { gy::input_mode::Write(previous_); }

  ScopedInputMode(const ScopedInputMode&) = delete;
  ScopedInputMode& operator=(const ScopedInputMode&) = delete;

private:
  int previous_;
};
}  // namespace

int main() {
  if (!UseIsolatedLocalAppData()) {
    std::wcerr << L"Cannot create an isolated local data directory for the smoke test.\n";
    return 2;
  }
  // Upgrade regression: an old generated schema must be replaced, otherwise an
  // existing user stays on the legacy page_size and cannot open a full grid.
  // This smoke test validates Chinese candidate quality. The runtime mode is
  // shared across applications, so isolate the test from the user's current EN
  // or Traditional selection and restore it automatically on every exit path.
  const ScopedInputMode simplified_mode(gy::input_mode::kSimplified);
  if (!SeedStaleGeneratedSchema()) {
    std::wcerr << L"Cannot seed a stale generated Rime schema.\n";
    return 11;
  }
  if (!SeedVerifiedEnglishLexicon()) {
    std::wcerr << L"Cannot seed the verified English lexicon snapshot.\n";
    return 19;
  }
  const std::wstring settings = g_local_app_data + L"\\GYInput\\settings.ini";
  HANDLE settings_file = CreateFileW(settings.c_str(), GENERIC_WRITE, 0, nullptr,
                                     CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (settings_file == INVALID_HANDLE_VALUE) return 4;
  const wchar_t bom = 0xFEFF;
  DWORD written = 0;
  const bool unicode_ini = WriteFile(settings_file, &bom, sizeof(bom), &written, nullptr) &&
      written == sizeof(bom);
  CloseHandle(settings_file);
  if (!unicode_ini ||
      !WritePrivateProfileStringW(L"MixedInput", L"Enabled", L"1", settings.c_str())) return 4;
  PinyinEngine engine(ModuleDirectory());
  if (!engine.IsReady()) {
    std::wcerr << L"PinyinEngine did not initialize librime: " << engine.Diagnostic() << L"\n";
    return 1;
  }
  if (!FileContainsAscii(g_local_app_data + L"\\GYInput\\rime\\build\\luna_pinyin.schema.yaml", "page_size: 75")) {
    std::wcerr << L"The bundled Rime schema did not replace the stale generated cache.\n";
    return 12;
  }
  const auto candidates = engine.Lookup(L"nihao", gy::input_mode::kSimplified);
  for (const auto& candidate : candidates) std::wcout << candidate << L"\n";
  if (candidates.empty() || !UsesOnlyHanCharacters(candidates)) {
    std::wcerr << L"Candidate quality gate returned a non-Han value.\n";
    return 10;
  }
  const auto simplified_houmian = engine.LookupExact(L"houmian", gy::input_mode::kSimplified);
  const auto simplified_weishenme = engine.LookupExact(L"weishenme", gy::input_mode::kSimplified);
  const bool simplified_houmian_front =
      !simplified_houmian.empty() && simplified_houmian.front() == L"后面";
  const bool simplified_weishenme_front =
      !simplified_weishenme.empty() && simplified_weishenme.front() == L"为什么";
  const bool simplified_houmian_leak =
      std::any_of(simplified_houmian.begin(), simplified_houmian.end(),
                  [](const std::wstring& value) { return value.find(L'後') != std::wstring::npos; });
  const bool simplified_weishenme_leak =
      std::any_of(simplified_weishenme.begin(), simplified_weishenme.end(),
                  [](const std::wstring& value) {
                    return value.find(L'爲') != std::wstring::npos ||
                           value.find(L'麽') != std::wstring::npos;
                  });
  if (!simplified_houmian_front || !simplified_weishenme_front ||
      simplified_houmian_leak || simplified_weishenme_leak) {
    std::wcerr << L"OpenCC did not keep the complete simplified candidate pool in simplified script. "
               << L"houmian.size=" << simplified_houmian.size()
               << L", houmian.front-ok=" << simplified_houmian_front
               << L", houmian.leak=" << simplified_houmian_leak
               << L", weishenme.size=" << simplified_weishenme.size()
               << L", weishenme.front-ok=" << simplified_weishenme_front
               << L", weishenme.leak=" << simplified_weishenme_leak << L"\n";
    return 29;
  }
  // A malformed but high-confidence code has ordinary fallback choices in
  // slot one, leaving the visible correction policy free to insert 紧急 only
  // as the non-destructive red #2 suggestion.
  auto typo_candidates = engine.Lookup(L"jingi", gy::input_mode::kSimplified);
  const auto typo_corrections = gy::correction::InsertPinyinSpellingCorrection(
      &typo_candidates, L"jingi", gy::input_mode::kSimplified);
  if (typo_candidates.size() < 2 || typo_candidates.front() == L"紧急" ||
      typo_candidates[1] != L"紧急" || typo_corrections != std::vector<unsigned>{1}) {
    std::wcerr << L"Pinyin spelling correction did not stay visible behind the normal first choice.\n";
    return 25;
  }
  const auto english_like = engine.Lookup(L"like", gy::input_mode::kSimplified);
  const auto english_blue = engine.Lookup(L"blue", gy::input_mode::kSimplified);
  const auto chinese_lanse = engine.Lookup(L"lanse", gy::input_mode::kSimplified);
  const auto mixed_wolike = engine.Lookup(L"wolike", gy::input_mode::kSimplified);
  if (english_like.empty() || english_like.front() != L"like" ||
      english_blue.empty() || english_blue.front() != L"blue" ||
      chinese_lanse.empty() || chinese_lanse.front() != L"蓝色" ||
      mixed_wolike.empty() || mixed_wolike.front() != L"我 like") {
    std::wcerr << L"Verified mixed CN/EN candidate policy regressed.\n";
    return 20;
  }
  const auto paging_candidates = engine.Lookup(L"wo", gy::input_mode::kSimplified);
  // Paging is unlocked: single-syllable queries fill the pool with one-
  // character candidates too. The pool ceiling (75) and the base quality gate
  // (CJK ideographs only) still apply to every page, and a common single-
  // syllable query must produce more than one page of candidates.
  if (paging_candidates.size() > 75) {
    std::wcerr << L"Candidate pool exceeded its 75-entry ceiling.\n";
    return 8;
  }
  if (paging_candidates.size() <= 25 || !UsesOnlyHanCharacters(paging_candidates)) {
    std::wcerr << L"Single-syllable paging stayed locked at 25 or admitted a non-Han entry.\n";
    return 8;
  }
  const auto fallback_candidates = engine.Lookup(L"gei", gy::input_mode::kSimplified);
  // Product contract: a sparse exact syllable retains its exact first choice,
  // then draws enough de-duplicated candidates from its shorter valid prefix
  // (gei → ge) to fill the 5 × 5 page. "个" is the default Rime ge candidate
  // and demonstrates that the extra slots are genuine selectable candidates,
  // not repeated placeholders.
  if (fallback_candidates.size() < 25 || fallback_candidates.size() > 75 ||
      fallback_candidates.front() != L"给" ||
      std::find(fallback_candidates.begin() + 1, fallback_candidates.end(), L"个") == fallback_candidates.end() ||
      !UsesOnlyHanCharacters(fallback_candidates)) {
    std::wcerr << L"Sparse exact pinyin did not preserve its first candidate and fill from its prefix.\n";
    return 13;
  }
  if (!WritePrivateProfileStringW(L"Phrases", L"dz", L"地址|电子邮箱", settings.c_str()) ||
      !WritePrivateProfileStringW(L"Phrases", L"dizhi ", L" 地址 ", settings.c_str()) ||
      !WritePrivateProfileStringW(L"Phrases", L"zg", L"中国", settings.c_str()) ||
      !WritePrivateProfileStringW(L"Phrases", L"jf", L"爲什麽|後面", settings.c_str()) ||
      !WritePrivateProfileStringW(L"Input", L"Mode", L"1", settings.c_str())) return 4;
  const auto simplified_local_phrases = engine.Lookup(L"jf", gy::input_mode::kSimplified);
  if (simplified_local_phrases.size() < 2 ||
      simplified_local_phrases[0] != L"为什么" || simplified_local_phrases[1] != L"后面") {
    std::wcerr << L"Local phrases bypassed the complete OpenCC simplified conversion.\n";
    return 30;
  }
  // TSF instances use the shared registry mode at runtime. Make the smoke test
  // explicit and restore the user's mode automatically on every return path.
  const ScopedInputMode traditional_mode(gy::input_mode::kTraditional);
  if (gy::input_mode::Read() != gy::input_mode::kTraditional) {
    std::wcerr << L"Traditional mode was not persisted for the smoke test.\n";
    return 17;
  }
  gy::input_mode::Write(gy::input_mode::kEnglish);
  if (gy::input_mode::Read() != gy::input_mode::kEnglish ||
      gy::input_mode::ReadLastChineseMode() != gy::input_mode::kTraditional) {
    std::wcerr << L"EN mode did not retain its previous Chinese mode.\n";
    return 18;
  }
  const auto english_candidates = engine.Lookup(L"wo", gy::input_mode::kEnglish);
  const std::vector<std::wstring> expected_english_front{
      L"word", L"work", L"world", L"would", L"woman", L"worker"};
  if (english_candidates.size() != gy::english_candidates::kExpandedVisible ||
      !std::equal(expected_english_front.begin(), expected_english_front.end(),
                  english_candidates.begin())) {
    std::wcerr << L"Pure EN candidate lookup did not return the bounded high-confidence top eight.\n";
    return 21;
  }
  const auto english_word_candidates = engine.Lookup(L"english", gy::input_mode::kEnglish);
  const auto likely_candidates = engine.Lookup(L"lik", gy::input_mode::kEnglish);
  const auto short_prefix_candidates = engine.Lookup(L"a", gy::input_mode::kEnglish);
  if (english_word_candidates.size() < 5 || english_word_candidates.front() != L"english" ||
      std::find(english_word_candidates.begin(), english_word_candidates.end(), L"englishman") ==
          english_word_candidates.end() ||
      likely_candidates.size() > 8 || likely_candidates.empty() || likely_candidates.front() != L"like" ||
      short_prefix_candidates.size() > 8 || short_prefix_candidates.empty() || short_prefix_candidates.front() != L"about") {
    std::wcerr << L"The bundled English baseline did not keep sparse suggestions inside the top-eight contract.\n";
    return 28;
  }
  // Per-request mode is authoritative even when persisted defaults disagree.
  // GY_TESTING substitutes test-input-mode.ini for the live HKCU channel, so
  // this reproduces registry=Chinese/settings.ini=EN without touching HKCU.
  if (!WritePrivateProfileStringW(L"Input", L"Mode", L"2", settings.c_str())) return 27;
  gy::input_mode::Write(gy::input_mode::kSimplified);
  if (gy::input_mode::Read() != gy::input_mode::kSimplified ||
      GetPrivateProfileIntW(L"Input", L"Mode", -1, settings.c_str()) != gy::input_mode::kEnglish) {
    std::wcerr << L"Could not create the isolated live-mode/ini conflict fixture.\n";
    return 27;
  }
  const auto conflicted_english = engine.Lookup(L"wo", gy::input_mode::kEnglish);
  const auto english_nonprefix = engine.Lookup(L"zhongw", gy::input_mode::kEnglish);
  if (conflicted_english.size() != gy::english_candidates::kExpandedVisible ||
      !std::equal(expected_english_front.begin(), expected_english_front.end(),
                  conflicted_english.begin()) ||
      !english_nonprefix.empty()) {
    std::wcerr << L"Persisted Chinese mode overrode an explicit EN lookup snapshot.\n";
    return 27;
  }
  const auto completed_english = engine.Lookup(L"word", gy::input_mode::kEnglish);
  if (completed_english.size() < 5 || completed_english.front() != L"word" ||
      std::find(completed_english.begin(), completed_english.end(), L"work") == completed_english.end() ||
      std::find(completed_english.begin(), completed_english.end(), L"world") == completed_english.end()) {
    std::wcerr << L"A completed English word did not keep a 3-5 local suggestion strip.\n";
    return 24;
  }
  gy::input_mode::Write(gy::input_mode::kTraditional);
  const auto phrase_candidates = engine.Lookup(L"dz", gy::input_mode::kTraditional);
  if (phrase_candidates.size() < 2 || phrase_candidates[0] != L"地址" || phrase_candidates[1] != L"電子郵箱" ||
      !UsesOnlyHanCharacters(phrase_candidates)) {
    std::wcerr << L"Custom phrases were missing or used the wrong script.\n";
    return 5;
  }
  const auto trimmed_phrase_candidates = engine.Lookup(L"dizhi", gy::input_mode::kTraditional);
  if (trimmed_phrase_candidates.empty() || trimmed_phrase_candidates.front() != L"地址") {
    std::wcerr << L"A spaced custom phrase key was not normalized.\n";
    return 7;
  }

  const auto traditional_candidates = engine.Lookup(L"zg", gy::input_mode::kTraditional);
  if (traditional_candidates.empty() || traditional_candidates.front() != L"中國") {
    std::wcerr << L"Traditional mode did not normalize custom phrase output.\n";
    return 9;
  }
  // Stable memory contract: only three explicit selections arm a candidate;
  // the following lookup (the user's fourth entry) is the first time it may
  // occupy slot 1.  Use words absent from the base nihao ranking so the test
  // proves promotion rather than inheriting the dictionary's own order.
  const std::wstring learned_candidate = L"超人";
  engine.Learn(L"nihao", learned_candidate);
  const auto one_time = engine.GetLearningSummary(L"nihao", learned_candidate);
  if (one_time.count != 1 || one_time.tier != PinyinEngine::LearningTier::Observed || one_time.armed) {
    std::wcerr << L"The first explicit selection changed the stable learning order.\n";
    return 6;
  }
  const auto weak_candidates = engine.Lookup(L"nihao", gy::input_mode::kTraditional);
  if (weak_candidates.empty() || weak_candidates.front() == learned_candidate ||
      std::find(weak_candidates.begin(), weak_candidates.end(), learned_candidate) == weak_candidates.end()) {
    std::wcerr << L"A weak learned candidate displaced or left the candidate pool.\n";
    return 15;
  }
  engine.Learn(L"nihao", learned_candidate);
  const auto repeated = engine.GetLearningSummary(L"nihao", learned_candidate);
  const auto twice_candidates = engine.Lookup(L"nihao", gy::input_mode::kTraditional);
  if (repeated.count != 2 || repeated.tier != PinyinEngine::LearningTier::Observed || repeated.armed ||
      twice_candidates.empty() || twice_candidates.front() == learned_candidate) {
    std::wcerr << L"Two explicit selections changed the stable learning order.\n";
    return 6;
  }
  engine.Learn(L"nihao", learned_candidate);
  const auto armed = engine.GetLearningSummary(L"nihao", learned_candidate);
  const auto learned_candidates = engine.Lookup(L"nihao", gy::input_mode::kTraditional);
  if (armed.count != 3 || armed.tier != PinyinEngine::LearningTier::Armed || !armed.armed ||
      learned_candidates.empty() || learned_candidates.front() != learned_candidate) {
    std::wcerr << L"The third explicit selection did not arm fourth-entry promotion.\n";
    return 6;
  }
  const std::wstring replacement_candidate = L"世人";
  engine.Learn(L"nihao", replacement_candidate);
  engine.Learn(L"nihao", replacement_candidate);
  if (engine.Lookup(L"nihao", gy::input_mode::kTraditional).empty() ||
      engine.Lookup(L"nihao", gy::input_mode::kTraditional).front() != learned_candidate) {
    std::wcerr << L"A competing candidate replaced the preference before three explicit selections.\n";
    return 22;
  }
  engine.Learn(L"nihao", replacement_candidate);
  if (engine.Lookup(L"nihao", gy::input_mode::kTraditional).empty() ||
      engine.Lookup(L"nihao", gy::input_mode::kTraditional).front() != replacement_candidate) {
    std::wcerr << L"A three-selection competing candidate did not replace the preference.\n";
    return 23;
  }
  if (!engine.SetLearningPinned(L"nihao", learned_candidate, true) ||
      engine.GetLearningSummary(L"nihao", learned_candidate).tier != PinyinEngine::LearningTier::Fixed) {
    std::wcerr << L"Pinned learning did not become a fixed entry.\n";
    return 16;
  }
  const std::wstring learned_sentence = L"今晚打老虎";
  engine.Learn(L"jinwandalaohu", learned_sentence);
  const auto learned_sentence_candidates = engine.Lookup(L"jinwandalaohu", gy::input_mode::kTraditional);
  if (std::find(learned_sentence_candidates.begin(), learned_sentence_candidates.end(), learned_sentence) ==
      learned_sentence_candidates.end()) {
    std::wcerr << L"Sentence learning did not retain the selected full phrase.\n";
    return 14;
  }
  // Settings “clear learning” deletes LearningStats too.  Recreating the
  // engine after the two local sections are cleared must not resurrect a
  // three-confirmation preference from its legacy compatibility record.
  if (!WritePrivateProfileStringW(L"Learning", nullptr, nullptr, settings.c_str()) ||
      !WritePrivateProfileStringW(L"LearningStats", nullptr, nullptr, settings.c_str())) {
    std::wcerr << L"Could not clear isolated learning storage.\n";
    return 26;
  }
  const auto cleared_summary = engine.GetLearningSummary(L"nihao", learned_candidate);
  const auto cleared_candidates = engine.Lookup(L"nihao", gy::input_mode::kTraditional);
  if (cleared_summary.count != 0 || cleared_summary.armed ||
      (!cleared_candidates.empty() && cleared_candidates.front() == learned_candidate)) {
    std::wcerr << L"Clearing local learning did not remove the stable preference.\n";
    return 26;
  }
  return 0;
}
