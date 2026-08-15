#pragma once

#include <windows.h>

namespace gy::punctuation {

// Chinese mode uses the standard CJK punctuation set. English mode, and a
// Chinese-mode field whose latest committed text was ASCII, are passed through
// unchanged to the application.
constexpr wchar_t ChineseCharacter(WPARAM key, bool shift) {
  switch (key) {
    case VK_OEM_COMMA:  return shift ? L'《' : L'，';
    case VK_OEM_PERIOD: return shift ? L'》' : L'。';
    case VK_OEM_1:      return shift ? L'：' : L'；';
    case VK_OEM_2:      return shift ? L'？' : L'、';
    case VK_OEM_4:      return shift ? L'｛' : L'【';
    case VK_OEM_6:      return shift ? L'｝' : L'】';
    case '1':           return shift ? L'！' : 0;
    default:             return 0;
  }
}
constexpr bool IsQuoteKey(WPARAM key) { return key == VK_OEM_7; }
constexpr bool IsPunctuationKey(WPARAM key, bool shift) {
  return IsQuoteKey(key) || ChineseCharacter(key, shift) != 0;
}
constexpr bool ShouldUseEnglishPunctuation(bool english_mode,
                                            bool composition_active,
                                            bool last_commit_was_ascii) {
  return english_mode || (!composition_active && last_commit_was_ascii);
}
constexpr wchar_t QuoteCharacter(bool double_quote, bool opening) {
  if (double_quote) return opening ? L'“' : L'”';
  return opening ? L'‘' : L'’';
}

}  // namespace gy::punctuation
