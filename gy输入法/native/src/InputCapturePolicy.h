#pragma once

#include <windows.h>

#include "KeyPolicy.h"

namespace gy::input_capture {

// The one place where TSF decides whether GY owns a keystroke. Both Chinese
// and pure EN are candidate modes. Password, URL, terminal and other direct
// fields are rejected by GyIme before this policy is reached.
constexpr bool ShouldCapture(bool english_mode,
                             bool has_shortcut_modifier,
                             bool shift_down,
                             bool composition_active,
                             unsigned current_page_candidate_count,
                             unsigned total_candidate_count,
                             WPARAM key,
                             bool use_english_punctuation,
                             bool english_list_open = false) {
  // Both English and Chinese are candidate modes; the caller has already
  // rejected password/URL/terminal direct-input fields.
  if (has_shortcut_modifier) return false;
  // Tab is form navigation except for an active EN suggestion, where it is
  // the conventional explicit accept action. Chinese composition keeps Tab
  // fully owned by the focused application.
  if (key == VK_TAB) return english_mode && composition_active && total_candidate_count != 0;
  if (use_english_punctuation && gy::punctuation::IsPunctuationKey(key, shift_down)) return false;
  if (gy::keys::ShouldCaptureChinesePunctuation(key, shift_down)) return true;
  // Shift+letter is real text in pure EN and must stay in the active
  // composition so Today/GPT/ThinkPad keep their casing. Chinese continues to
  // pass shifted letters to the focused application.
  if (shift_down && !(english_mode && key >= 'A' && key <= 'Z')) return false;
  if (key >= 'A' && key <= 'Z') return true;
  // EN has no numeric candidate shortcuts. Digits stay in the literal
  // composition and are appended by GyIme instead of selecting a word.
  if (english_mode && key >= '0' && key <= '9') return true;
  // Candidate rendering can briefly outlive the composition-state update in
  // TSF. While a candidate page is visible, navigation must remain owned by
  // GY; otherwise Windows delivers ↓ to the application instead of opening
  // the 5 × 5 grid.
  // Composition state can lag behind an already visible candidate window.
  // Keep navigation inside GY while the complete candidate pool is non-empty.
  if (!composition_active && total_candidate_count == 0) return false;

  // EN has a bounded explicit list, never Chinese paging. Down opens or moves
  // through it; Up becomes owned by GY only once the list is open. Page keys
  // remain with the focused application.
  if (english_mode) {
    if (key == VK_DOWN) return total_candidate_count != 0;
    if (key == VK_UP) return english_list_open;
    return key == VK_OEM_7 || key == VK_BACK || key == VK_ESCAPE ||
        gy::keys::IsCommitKey(key) || key == VK_LEFT || key == VK_RIGHT;
  }

  if (key == VK_OEM_7 || key == VK_BACK || key == VK_ESCAPE ||
      gy::keys::IsCommitKey(key) || key == VK_UP || key == VK_DOWN ||
      key == VK_LEFT || key == VK_RIGHT || key == VK_PRIOR || key == VK_NEXT) {
    return true;
  }
  if (key >= '1' && key <= '5') {
    return !english_mode && static_cast<unsigned>(key - '1') < current_page_candidate_count;
  }
  return false;
}

// Compatibility overload for callers that provide both candidate counts but
// do not need the automatic English-punctuation decision.
constexpr bool ShouldCapture(bool english_mode,
                             bool has_shortcut_modifier,
                             bool shift_down,
                             bool composition_active,
                             unsigned current_page_candidate_count,
                             unsigned total_candidate_count,
                             WPARAM key) {
  return ShouldCapture(english_mode, has_shortcut_modifier, shift_down,
                       composition_active, current_page_candidate_count,
                       total_candidate_count, key, false);
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
                       current_page_candidate_count, key, false);
}

}  // namespace gy::input_capture
