#pragma once

#include <windows.h>

namespace gy::numeric_entry {

// Numeric entry is a tiny local state machine. It never reads the control's
// text: the only state is whether GY itself just delivered a number fragment.
// This lets Chinese composition coexist with versions, dates, times and
// percentages without guessing a password, account or surrounding content.
constexpr wchar_t CharacterFor(WPARAM key, bool shift, bool fragment_active) noexcept {
  if (key >= L'0' && key <= L'9') {
    if (!shift) return static_cast<wchar_t>(key);
    return fragment_active && key == L'5' ? L'%' : 0;
  }
  if (!fragment_active) return 0;
  switch (key) {
    case VK_OEM_PERIOD: return shift ? 0 : L'.';
    case VK_OEM_MINUS: return shift ? 0 : L'-';
    case VK_OEM_1: return shift ? L':' : 0;
    case VK_OEM_2: return shift ? 0 : L'/';
    default: return 0;
  }
}

constexpr bool StartsFragment(WPARAM key, bool shift) noexcept {
  return key >= L'0' && key <= L'9' && !shift;
}

constexpr bool Accepts(WPARAM key, bool shift, bool fragment_active) noexcept {
  return CharacterFor(key, shift, fragment_active) != 0;
}

}  // namespace gy::numeric_entry
