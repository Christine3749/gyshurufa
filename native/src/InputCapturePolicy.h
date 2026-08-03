#pragma once

#include <windows.h>

#include "KeyPolicy.h"

namespace gy::input_capture {

// The one place where TSF decides whether GY owns a keystroke. Keep this
// policy UI-free so native smoke tests can lock the EN-direct contract:
// English and application shortcuts always belong to the focused app.
constexpr bool ShouldCapture(bool english_mode,
                             bool has_shortcut_modifier,
                             bool shift_down,
                             bool composition_active,
                             unsigned current_page_candidate_count,
                             WPARAM key) {
  if (english_mode || has_shortcut_modifier) return false;
  if (gy::keys::ShouldCaptureChinesePunctuation(key, shift_down)) return true;
  if (shift_down) return false;
  if (key >= 'A' && key <= 'Z') return true;
  if (!composition_active) return false;

  if (key == VK_OEM_7 || key == VK_BACK || key == VK_ESCAPE ||
      gy::keys::IsCommitKey(key) || key == VK_UP || key == VK_DOWN ||
      key == VK_LEFT || key == VK_RIGHT || key == VK_PRIOR || key == VK_NEXT) {
    return true;
  }
  if (key >= '1' && key <= '5') {
    return static_cast<unsigned>(key - '1') < current_page_candidate_count;
  }
  return false;
}

}  // namespace gy::input_capture
