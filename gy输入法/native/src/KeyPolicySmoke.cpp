#include "KeyPolicy.h"
#include "InputMode.h"
#include "InputCapturePolicy.h"
#include "PunctuationPolicy.h"

#include <iostream>

int wmain() {
  if (!gy::keys::IsShiftKey(VK_SHIFT) || !gy::keys::IsShiftKey(VK_LSHIFT) ||
      !gy::keys::IsShiftKey(VK_RSHIFT) || gy::keys::IsShiftKey('A')) return 1;
  if (!gy::keys::ShouldCaptureShift(false) || gy::keys::ShouldCaptureShift(true)) return 2;
  if (!gy::keys::ShouldToggleMode(true, false, false)) return 3;
  if (gy::keys::ShouldToggleMode(true, true, false) ||
      gy::keys::ShouldToggleMode(true, false, true) ||
      gy::keys::ShouldToggleMode(false, false, false)) return 4;
  if (gy::punctuation::ChineseCharacter(VK_OEM_COMMA, false) != L'，' ||
      gy::punctuation::ChineseCharacter(VK_OEM_PERIOD, false) != L'。' ||
      gy::punctuation::ChineseCharacter(VK_OEM_2, true) != L'？' ||
      gy::punctuation::ChineseCharacter('1', true) != L'！' ||
      gy::punctuation::ChineseCharacter('1', false) != 0 ||
      gy::punctuation::QuoteCharacter(true, true) != L'“' ||
      gy::punctuation::QuoteCharacter(false, false) != L'’') return 6;  if (!gy::keys::ShouldMarkShiftUsed(true, VK_CONTROL) ||
      !gy::keys::ShouldMarkShiftUsed(true, 'A') ||
      !gy::keys::ShouldMarkShiftUsed(true, VK_TAB) ||
      gy::keys::ShouldMarkShiftUsed(true, VK_SHIFT) ||
      gy::keys::ShouldMarkShiftUsed(false, VK_CONTROL)) return 5;
  if (!gy::keys::ShouldCaptureChinesePunctuation(VK_OEM_COMMA, false) ||
      !gy::keys::ShouldCaptureChinesePunctuation(VK_OEM_PERIOD, false) ||
      !gy::keys::ShouldCaptureChinesePunctuation(VK_OEM_7, false) ||
      gy::keys::ShouldCaptureChinesePunctuation('A', false)) return 7;
  if (!gy::keys::IsRawTextCommitKey(VK_RETURN) || gy::keys::IsRawTextCommitKey(VK_SPACE) ||
      !gy::keys::IsCandidateCommitKey(VK_SPACE) || gy::keys::IsCandidateCommitKey(VK_RETURN) ||
      !gy::keys::IsCommitKey(VK_RETURN) || !gy::keys::IsCommitKey(VK_SPACE) ||
      gy::keys::IsCommitKey(VK_SHIFT)) return 8;
  // Compact Enter keeps raw pinyin available; grid Enter commits the selected
  // cell so arrow-key navigation has a keyboard confirmation path.
  if (gy::keys::ShouldCommitSelectedCandidate(VK_RETURN, false) ||
      !gy::keys::ShouldCommitSelectedCandidate(VK_RETURN, true) ||
      !gy::keys::ShouldCommitSelectedCandidate(VK_SPACE, false) ||
      !gy::keys::ShouldCommitSelectedCandidate(VK_SPACE, true) ||
      gy::keys::ShouldCommitSelectedCandidate(VK_TAB, true)) return 13;

  if (gy::input_mode::Normalize(-1) != gy::input_mode::kSimplified ||
      gy::input_mode::Normalize(99) != gy::input_mode::kEnglish ||
      !gy::input_mode::IsEnglish(gy::input_mode::kEnglish) ||
      gy::input_mode::IsEnglish(gy::input_mode::kSimplified)) return 9;

  // EN Direct is non-negotiable: all ordinary editing/navigation keys pass
  // through even if an older Chinese composition was still active.
  constexpr WPARAM kEnglishDirectKeys[] = {
      static_cast<WPARAM>('A'), VK_OEM_COMMA, VK_RETURN, VK_TAB,
      VK_BACK, VK_DOWN, VK_PRIOR, static_cast<WPARAM>('1')};
  for (const WPARAM key : kEnglishDirectKeys) {
    if (gy::input_capture::ShouldCapture(true, false, false, true, 5, key)) {
      return 10;
    }
  }
  // Command shortcuts are equally owned by the focused application.
  if (gy::input_capture::ShouldCapture(false, true, false, true, 5, 'V')) return 11;

  // Chinese mode owns letters, Chinese punctuation and composition navigation.
  if (!gy::input_capture::ShouldCapture(false, false, false, false, 0, 'A') ||
      !gy::input_capture::ShouldCapture(false, false, false, false, 0, VK_OEM_COMMA) ||
      !gy::input_capture::ShouldCapture(false, false, false, false, 5, VK_DOWN) ||
      !gy::input_capture::ShouldCapture(false, false, false, true, 5, VK_DOWN) ||
      !gy::input_capture::ShouldCapture(false, false, false, true, 5, VK_RETURN) ||
      !gy::input_capture::ShouldCapture(false, false, false, true, 5, '5') ||
      gy::input_capture::ShouldCapture(false, false, false, true, 4, '5') ||
      gy::input_capture::ShouldCapture(false, false, true, true, 5, 'A')) return 12;

  // Regression: candidates may remain visible while TSF composition is empty.
  if (!gy::input_capture::ShouldCapture(false, false, false, false, 0, 5, VK_DOWN) ||
      !gy::input_capture::ShouldCapture(false, false, false, false, 0, 5, VK_UP)) return 14;

  return 0;
}