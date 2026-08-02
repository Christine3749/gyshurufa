#pragma once

#include <windows.h>

namespace gy::punctuation {

// Chinese mode uses the standard CJK punctuation set. English mode deliberately
// does not call this mapper and is passed through unchanged to the application.
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
constexpr wchar_t QuoteCharacter(bool double_quote, bool opening) {
  if (double_quote) return opening ? L'“' : L'”';
  return opening ? L'‘' : L'’';
}

}  // namespace gy::punctuation