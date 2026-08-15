#pragma once

#include <string>
#include <string_view>
#include <vector>

namespace gy::english_assist {

// English Assist is intentionally a separate, opt-in layer. EN itself stays
// literal pass-through; this API is invoked only after the user explicitly
// selects text and presses the documented assist shortcut.
constexpr unsigned kMaximumSuggestions = 5;

bool IsEnabled();
void SetEnabled(bool enabled);

bool IsEligibleSelection(std::wstring_view text) noexcept;
std::vector<std::wstring> Suggest(std::wstring_view text,
                                  unsigned maximum = kMaximumSuggestions);

// An English-assist composition always retains the selected original unless
// the user explicitly accepts one of its suggestions. This gives Esc, a focus
// change, and a safety-boundary transition the same non-destructive outcome.
std::wstring ResolveCommitText(std::wstring_view original,
                              const std::vector<std::wstring>& suggestions,
                              unsigned index, bool accept_suggestion);

}  // namespace gy::english_assist
