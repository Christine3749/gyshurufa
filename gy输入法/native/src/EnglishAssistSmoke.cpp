#include "EnglishAssist.h"

#include <algorithm>

int wmain() {
  const std::wstring maximum_length(64, L'a');
  const std::wstring too_long(65, L'a');
  if (!gy::english_assist::IsEligibleSelection(L"recieve") ||
      !gy::english_assist::IsEligibleSelection(L"mother-in-law") ||
      !gy::english_assist::IsEligibleSelection(maximum_length) ||
      gy::english_assist::IsEligibleSelection(too_long) ||
      gy::english_assist::IsEligibleSelection(L"a") ||
      gy::english_assist::IsEligibleSelection(L"two words") ||
      gy::english_assist::IsEligibleSelection(L"密码")) return 1;

  const auto suggestions = gy::english_assist::Suggest(L"recieve");
  if (suggestions.empty() ||
      std::find(suggestions.begin(), suggestions.end(), L"receive") == suggestions.end() ||
      suggestions.size() > gy::english_assist::kMaximumSuggestions) return 2;
  const auto receive = static_cast<unsigned>(std::find(suggestions.begin(), suggestions.end(), L"receive") -
                                             suggestions.begin());
  if (gy::english_assist::ResolveCommitText(L"recieve", suggestions, receive, false) != L"recieve" ||
      gy::english_assist::ResolveCommitText(L"recieve", suggestions, receive, true) != L"receive") return 3;
  return 0;
}
