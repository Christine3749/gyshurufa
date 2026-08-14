#include "CorrectionPolicy.h"

#include <iostream>
#include <vector>

int wmain() {
  std::vector<std::wstring> simplified{L"进", L"京", L"景"};
  const auto simplified_indexes = gy::correction::InsertPinyinSpellingCorrection(
      &simplified, L"jingi", 0);
  if (simplified.size() != 4 || simplified[0] != L"进" || simplified[1] != L"紧急" ||
      simplified_indexes != std::vector<unsigned>{1}) {
    std::wcerr << L"Simplified spelling correction did not stay behind slot one.\n";
    return 1;
  }

  std::vector<std::wstring> traditional{L"進", L"京"};
  const auto traditional_indexes = gy::correction::InsertPinyinSpellingCorrection(
      &traditional, L"JINGI", 1);
  if (traditional[0] != L"進" || traditional[1] != L"緊急" ||
      traditional_indexes != std::vector<unsigned>{1}) {
    std::wcerr << L"Traditional spelling correction used the wrong script.\n";
    return 2;
  }

  std::vector<std::wstring> first_item_is_normal{L"紧急", L"京"};
  if (!gy::correction::InsertPinyinSpellingCorrection(&first_item_is_normal, L"jingi", 0).empty() ||
      first_item_is_normal[0] != L"紧急") {
    std::wcerr << L"A correction changed or annotated the normal first candidate.\n";
    return 3;
  }

  std::vector<std::wstring> no_normal_candidate;
  if (!gy::correction::InsertPinyinSpellingCorrection(&no_normal_candidate, L"jingi", 0).empty() ||
      !no_normal_candidate.empty()) {
    std::wcerr << L"A correction was promoted to the first candidate.\n";
    return 4;
  }
  return 0;
}
