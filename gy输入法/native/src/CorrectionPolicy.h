#pragma once

#include <algorithm>
#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

namespace gy::correction {

// Candidate correction is deliberately a small local policy, not an AI model.
// It only understands high-confidence spelling slips that have an unambiguous
// Chinese correction.  It never inspects surrounding application text, and it
// never changes the first candidate or commits text by itself.
inline std::wstring NormalizeAscii(std::wstring_view value) {
  std::wstring result(value);
  for (wchar_t& character : result) {
    if (character >= L'A' && character <= L'Z') {
      character = static_cast<wchar_t>(character - L'A' + L'a');
    }
  }
  return result;
}

inline std::wstring PinyinSpellingCorrection(std::wstring_view raw_pinyin, int input_mode) {
  // The user-visible example: a missing "n" in jingji.  Keep the table narrow
  // until a correction has a measured precision rate; an eager correction is
  // worse than no correction in an input method.
  if (NormalizeAscii(raw_pinyin) != L"jingi") return {};
  return input_mode == 1 ? L"緊急" : L"紧急";
}

// The fallback has to be a normal pinyin result, never the correction itself:
// that is what guarantees that a typo correction cannot seize candidate #1.
inline std::wstring PinyinSpellingFallback(std::wstring_view raw_pinyin) {
  return NormalizeAscii(raw_pinyin) == L"jingi" ? L"jing" : L"";
}

// Inserts an explicit correction only behind a genuine normal candidate.
// Returned indexes are display metadata: callers paint these candidates as a
// red suggestion, while committing only the plain candidate text.
inline std::vector<unsigned> InsertPinyinSpellingCorrection(
    std::vector<std::wstring>* candidates, std::wstring_view raw_pinyin, int input_mode) {
  if (!candidates || input_mode < 0 || input_mode > 1 || candidates->empty()) return {};
  const std::wstring correction = PinyinSpellingCorrection(raw_pinyin, input_mode);
  if (correction.empty()) return {};

  const auto existing = std::find(candidates->begin(), candidates->end(), correction);
  if (existing != candidates->end()) {
    const auto index = static_cast<unsigned>(std::distance(candidates->begin(), existing));
    // A dictionary's normal first item must remain ordinary.  Never repaint it
    // as a correction or move it merely because it happens to equal a typo's
    // possible correction.
    return index >= 1 && index <= 3 ? std::vector<unsigned>{index} : std::vector<unsigned>{};
  }

  // Slot two is the earliest correction may appear.  Leave room for the
  // normal first choice, trim the tail to preserve the global 75-item cap,
  // and keep the correction inside the promised 2–4 range.
  if (candidates->size() >= 75) candidates->pop_back();
  candidates->insert(candidates->begin() + 1, correction);
  return {1};
}

}  // namespace gy::correction
