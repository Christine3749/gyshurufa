#include "KeyPolicy.h"
#include "InputMode.h"
#include "InputCapturePolicy.h"
#include "PunctuationPolicy.h"
#include "InputScopePolicy.h"

#include <iostream>

int wmain() {
  if (!gy::keys::IsShiftKey(VK_SHIFT) || !gy::keys::IsShiftKey(VK_LSHIFT) ||
      !gy::keys::IsShiftKey(VK_RSHIFT) || gy::keys::IsShiftKey('A')) return 1;
  if (!gy::keys::ShouldCaptureShift(false) || gy::keys::ShouldCaptureShift(true)) return 2;
  if (!gy::keys::ShouldToggleMode(true, false, false)) return 3;
  if (gy::keys::ShouldToggleMode(true, true, false) ||
      gy::keys::ShouldToggleMode(true, false, true) ||
      gy::keys::ShouldToggleMode(false, false, false)) return 4;
  if (!gy::keys::ShouldCancelCompositionBeforeModeSwitch(true, true) ||
      gy::keys::ShouldCancelCompositionBeforeModeSwitch(false, true) ||
      gy::keys::ShouldCancelCompositionBeforeModeSwitch(true, false)) return 17;
  if (!gy::punctuation::IsPunctuationKey(VK_OEM_COMMA, false) ||
      !gy::punctuation::IsPunctuationKey(VK_OEM_7, false) ||
      gy::punctuation::IsPunctuationKey('1', false) ||
      !gy::punctuation::IsPunctuationKey('1', true) ||
      !gy::punctuation::ShouldUseEnglishPunctuation(false, false, true) ||
      gy::punctuation::ShouldUseEnglishPunctuation(false, true, true) ||
      !gy::punctuation::ShouldUseEnglishPunctuation(true, true, false)) return 18;
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
  if (gy::keys::ShouldAcceptEnglishWithSpace(false) ||
      !gy::keys::ShouldAcceptEnglishWithSpace(true)) return 23;
  if (!gy::keys::ShouldCommitRawBeforeBoundary(true) ||
      gy::keys::ShouldCommitRawBeforeBoundary(false)) return 24;

  if (gy::input_mode::Normalize(-1) != gy::input_mode::kSimplified ||
      gy::input_mode::Normalize(99) != gy::input_mode::kEnglish ||
      !gy::input_mode::IsEnglish(gy::input_mode::kEnglish) ||
      gy::input_mode::IsEnglish(gy::input_mode::kSimplified) ||
      gy::input_mode::NormalizeChinese(gy::input_mode::kTraditional) != gy::input_mode::kTraditional ||
      gy::input_mode::NormalizeChinese(gy::input_mode::kEnglish) != gy::input_mode::kSimplified ||
      gy::input_mode::NormalizeChinese(-1) != gy::input_mode::kSimplified) return 9;

  // EN uses a lightweight suggestion strip. Tab is the conventional explicit
  // accept action there; Chinese keeps Tab as application navigation.
  constexpr WPARAM kEnglishCandidateKeys[] = {
      static_cast<WPARAM>('A'), VK_RETURN, VK_SPACE, VK_BACK, VK_LEFT,
      VK_RIGHT, static_cast<WPARAM>('1')};
  for (const WPARAM key : kEnglishCandidateKeys) {
    if (!gy::input_capture::ShouldCapture(true, false, false, true, 5, key)) {
      return 10;
    }
  }
  if (!gy::input_capture::ShouldCapture(true, false, false, true, 5, VK_TAB) ||
      gy::input_capture::ShouldCapture(true, false, false, true, 5, VK_OEM_COMMA, true)) return 10;
  if (gy::input_capture::ShouldCapture(true, false, false, true, 5, VK_UP) ||
      !gy::input_capture::ShouldCapture(true, false, false, true, 5, VK_DOWN) ||
      gy::input_capture::ShouldCapture(true, false, false, true, 5, VK_PRIOR) ||
      gy::input_capture::ShouldCapture(true, false, false, true, 5, VK_NEXT)) return 22;
  if (!gy::input_capture::ShouldCapture(true, false, false, true, 5, 8, VK_UP, false, true) ||
      !gy::input_capture::ShouldCapture(true, false, true, true, 5, 8, 'T', false, false)) return 25;
  // Pure EN digits are literal composition text, never 1-5 shortcuts.
  if (!gy::input_capture::ShouldCapture(true, false, false, true, 5, 20, '1') ||
      !gy::input_capture::ShouldCapture(true, false, false, true, 5, 20, '9')) return 21;
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

  if (gy::input_capture::ShouldCapture(false, false, false, false, 0, 0, VK_OEM_COMMA, true) ||
      gy::input_capture::ShouldCapture(false, false, false, false, 0, 0, VK_OEM_7, true) ||
      !gy::input_capture::ShouldCapture(false, false, false, false, 0, 0, VK_OEM_COMMA, false)) return 19;

  // Chinese Tab navigation belongs to the focused application in every state.
  if (gy::input_capture::ShouldCapture(false, false, false, false, 0, 0, VK_TAB) ||
      gy::input_capture::ShouldCapture(false, false, false, true, 5, 5, VK_TAB) ||
      gy::input_capture::ShouldCapture(false, false, true, true, 5, 5, VK_TAB) ||
      gy::input_capture::ShouldCapture(false, false, false, true, 5, 5, VK_TAB)) return 15;

  // Password, PIN and login-oriented fields are direct-input contexts;
  // chat/search fields remain ordinary Chinese-capable contexts.
  if (!gy::input_scope::IsDirectInput(IS_PASSWORD) ||
      !gy::input_scope::IsDirectInput(IS_NUMERIC_PASSWORD) ||
      !gy::input_scope::IsDirectInput(IS_LOGINNAME) ||
      !gy::input_scope::IsDirectInput(IS_EMAIL_SMTPEMAILADDRESS) ||
      !gy::input_scope::IsDirectInput(IS_URL) ||
      !gy::input_scope::IsPasswordContext(IS_PASSWORD) ||
       !gy::input_scope::IsPasswordContext(IS_ALPHANUMERIC_PIN) ||
       !gy::input_scope::IsSensitiveDirectInput(IS_PASSWORD) ||
       gy::input_scope::IsSensitiveDirectInput(IS_URL) ||
       !gy::input_scope::IsHardDirectCaptureBoundary(true) ||
       gy::input_scope::IsHardDirectCaptureBoundary(false) ||
       gy::input_scope::IsPasswordContext(IS_EMAIL_SMTPEMAILADDRESS) ||
      gy::input_scope::IsDirectInput(IS_CHAT) ||
      gy::input_scope::IsDirectInput(IS_SEARCH)) return 16;

  // Browser/Electron fallback: only accessibility labels are classified. The
  // actual text typed into a control is never inspected by this policy.
  if (!gy::input_scope::IsEnglishAutomationHint(L"Email address") ||
      !gy::input_scope::IsEnglishAutomationHint(L"请输入密码") ||
      !gy::input_scope::IsEnglishAutomationHint(L"One-time verification code") ||
       gy::input_scope::IsEnglishAutomationHint(L"账号") ||
      !gy::input_scope::IsSensitiveAutomationHint(L"请输入密码") ||
      !gy::input_scope::IsSensitiveAutomationHint(L"One-time verification code") ||
      gy::input_scope::IsSensitiveAutomationHint(L"Email address") ||
      gy::input_scope::IsEnglishAutomationHint(L"搜索全部笔记") ||
      gy::input_scope::IsEnglishAutomationHint(L"聊天消息")) return 20;

  return 0;
}
