#include "KeyPolicy.h"
#include "InputMode.h"
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

  if (gy::input_mode::Normalize(-1) != gy::input_mode::kSimplified ||
      gy::input_mode::Normalize(99) != gy::input_mode::kEnglish ||
      !gy::input_mode::IsEnglish(gy::input_mode::kEnglish) ||
      gy::input_mode::IsEnglish(gy::input_mode::kSimplified)) return 9;

  return 0;
}