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
                             unsigned total_candidate_count,
                             WPARAM key) {
  if (english_mode || has_shortcut_modifier) return false;
  if (gy::keys::ShouldCaptureChinesePunctuation(key, shift_down)) return true;
  if (shift_down) return false;
  if (key >= 'A' && key <= 'Z') return true;
  // Candidate rendering can briefly outlive the composition-state update in
  // TSF. While a candidate page is visible, navigation must remain owned by
  // GY; otherwise Windows delivers ↓ to the application instead of opening
  // the 5 × 5 grid.
  // Composition state can lag behind an already visible candidate window.
  // Keep navigation inside GY while the complete candidate pool is non-empty.
  if (!composition_active && total_candidate_count == 0) return false;

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

// Compatibility overload for callers that only have the visible page count.
constexpr bool ShouldCapture(bool english_mode,
                             bool has_shortcut_modifier,
                             bool shift_down,
                             bool composition_active,
                             unsigned current_page_candidate_count,
                             WPARAM key) {
  return ShouldCapture(english_mode, has_shortcut_modifier, shift_down,
                       composition_active, current_page_candidate_count,
                       current_page_candidate_count, key);
}

}  // namespace gy::input_capture
