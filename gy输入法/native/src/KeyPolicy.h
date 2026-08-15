#pragma once

#include <windows.h>

#include "PunctuationPolicy.h"

namespace gy::keys {
constexpr bool IsShiftKey(WPARAM key) {
  return key == VK_SHIFT || key == VK_LSHIFT || key == VK_RSHIFT;
}

// A lone Shift is the explicit GY mode shortcut. Shift used with Ctrl, Alt or
// Win belongs to Windows or the focused application and must never be claimed.
constexpr bool ShouldCaptureShift(bool has_shortcut_modifier) {
  return !has_shortcut_modifier;
}

constexpr bool ShouldToggleMode(bool shift_down, bool shift_used, bool has_shortcut_modifier) {
  return shift_down && !shift_used && !has_shortcut_modifier;
}

// Switching from Chinese composition to EN must preserve the literal ASCII
// text already being edited. Switching into EN discards only unconfirmed
// pinyin: GY never silently commits raw text or a Chinese candidate as a side
// effect of changing modes.
constexpr bool ShouldCancelCompositionBeforeModeSwitch(bool has_composition, bool next_english) {
  return has_composition && next_english;
}

// TSF may not call OnKeyDown for a key that we deliberately pass to the app.
// Mark the pending Shift as used during the Test phase, so Shift+Tab,
// Shift+letter and Shift+Ctrl cannot become a mode toggle when Shift is released.
constexpr bool ShouldMarkShiftUsed(bool shift_down, WPARAM key) {
  return shift_down && !IsShiftKey(key);
}

constexpr bool ShouldCaptureChinesePunctuation(WPARAM key, bool shift) {
  return gy::punctuation::IsQuoteKey(key) || gy::punctuation::ChineseCharacter(key, shift) != 0;
}

// Space confirms the active Chinese candidate. Enter commits raw pinyin as
// ASCII text in the compact row, but confirms the actively highlighted item
// after the user explicitly opens the candidate grid. This gives the grid a
// standard move-then-Enter path without changing raw-pinyin entry.
constexpr bool IsCandidateCommitKey(WPARAM key) { return key == VK_SPACE; }
constexpr bool IsRawTextCommitKey(WPARAM key) { return key == VK_RETURN; }
constexpr bool ShouldCommitSelectedCandidate(WPARAM key, bool expanded_candidates) {
  return IsCandidateCommitKey(key) || (expanded_candidates && key == VK_RETURN);
}
constexpr bool IsCommitKey(WPARAM key) { return IsCandidateCommitKey(key) || IsRawTextCommitKey(key); }

// Punctuation is a word boundary, not an implicit completion command. In EN
// it preserves the literal token, just like Space and Enter.
constexpr bool ShouldCommitRawBeforeBoundary(bool english_mode) noexcept {
  return english_mode;
}

// Space remains literal in the passive EN strip. After the user deliberately
// focuses candidates with an arrow, it accepts that highlighted completion
// and adds the normal word-boundary space.
constexpr bool ShouldAcceptEnglishWithSpace(bool candidate_focus) noexcept {
  return candidate_focus;
}
}  // namespace gy::keys
