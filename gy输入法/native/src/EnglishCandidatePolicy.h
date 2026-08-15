#pragma once

#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

namespace gy::english_candidates {

// A typed English suggestion carries commit semantics. Do not reduce these to
// a string list when correction and next-word prediction are introduced: a
// completion appends a suffix, a correction replaces the current token, and a
// next-word result starts after a word boundary.
enum class Kind : unsigned {
  Completion = 0,
  Correction = 1,
  NextWord = 2,
};

enum class Source : unsigned {
  LocalLexicon = 0,
  LocalCorrection = 1,
  LocalLanguageModel = 2,
  PersonalLexicon = 3,
};

struct Candidate {
  Kind kind = Kind::Completion;
  std::wstring display_text;
  std::wstring commit_text;
  std::size_t replace_begin = 0;
  std::size_t replace_end = 0;
  unsigned confidence = 0;
  Source source = Source::LocalLexicon;
};

struct CandidateSet {
  std::vector<Candidate> candidates;
  unsigned long long input_generation = 0;
  bool selection_locked = false;
};

// EN deliberately has two bounded surfaces. The passive strip stays small,
// while an explicit Down action can reveal a few more high-confidence local
// completions without turning English into the Chinese paging browser.
constexpr unsigned kCompactVisible = 5;
constexpr unsigned kExpandedVisible = 8;
constexpr unsigned kMaximumVisible = kExpandedVisible;

inline wchar_t AsciiLower(wchar_t character) noexcept {
  return character >= L'A' && character <= L'Z'
      ? static_cast<wchar_t>(character - L'A' + L'a') : character;
}

inline wchar_t AsciiUpper(wchar_t character) noexcept {
  return character >= L'a' && character <= L'z'
      ? static_cast<wchar_t>(character - L'a' + L'A') : character;
}

inline std::wstring PreserveTypedCase(std::wstring_view composition,
                                      std::wstring_view word) {
  if (composition.size() > word.size()) return std::wstring(word);
  for (std::size_t index = 0; index < composition.size(); ++index) {
    if (AsciiLower(composition[index]) != AsciiLower(word[index])) {
      return std::wstring(word);
    }
  }

  bool saw_letter = false;
  bool all_upper = true;
  bool title_case = false;
  for (std::size_t index = 0; index < composition.size(); ++index) {
    const wchar_t character = composition[index];
    if ((character >= L'A' && character <= L'Z') ||
        (character >= L'a' && character <= L'z')) {
      if (!saw_letter) title_case = character >= L'A' && character <= L'Z';
      saw_letter = true;
      if (character < L'A' || character > L'Z') all_upper = false;
    }
  }

  std::wstring result(word);
  if (saw_letter && all_upper) {
    for (wchar_t& character : result) character = AsciiUpper(character);
  } else if (title_case && !result.empty()) {
    result.front() = AsciiUpper(result.front());
  }
  // The already typed prefix is immutable, including deliberate product-name
  // casing such as iP or Mac. Only the untyped suffix comes from the lexicon.
  result.replace(0, composition.size(), composition);
  return result;
}

inline Candidate Completion(std::wstring_view composition, std::wstring_view word,
                            unsigned confidence = 100) {
  const std::wstring cased_word = PreserveTypedCase(composition, word);
  return Candidate{Kind::Completion, cased_word, cased_word,
                   0, composition.size(), confidence, Source::LocalLexicon};
}

inline bool IsCommitValid(const Candidate& candidate, std::size_t composition_size) noexcept {
  return !candidate.commit_text.empty() && candidate.replace_begin <= candidate.replace_end &&
      candidate.replace_end <= composition_size;
}

inline std::wstring ResolveCommit(std::wstring_view composition, const Candidate& candidate) {
  if (!IsCommitValid(candidate, composition.size())) return std::wstring(composition);
  std::wstring result(composition.substr(0, candidate.replace_begin));
  result += candidate.commit_text;
  result += composition.substr(candidate.replace_end);
  return result;
}

inline std::vector<Candidate> CompletionCandidates(
    std::wstring_view composition, const std::vector<std::wstring>& words) {
  std::vector<Candidate> result;
  result.reserve(words.size() < kMaximumVisible ? words.size() : kMaximumVisible);
  for (const std::wstring& word : words) {
    if (result.size() >= kMaximumVisible) break;
    result.push_back(Completion(composition, word));
  }
  return result;
}

constexpr bool CanApplyAsyncResult(unsigned long long result_generation,
                                   unsigned long long current_generation,
                                   bool selection_locked) noexcept {
  return result_generation == current_generation && !selection_locked;
}

constexpr bool CanCommitCandidate(unsigned long long requested_generation,
                                  unsigned long long current_generation) noexcept {
  return requested_generation == current_generation;
}

constexpr bool CanShowAtInputState(Kind kind, bool at_word_boundary) noexcept {
  return kind == Kind::NextWord ? at_word_boundary : !at_word_boundary;
}

}  // namespace gy::english_candidates
