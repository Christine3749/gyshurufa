#pragma once

#include <inputscope.h>
#include <string_view>

namespace gy::input_scope {

// These scopes describe fields where Chinese composition is not useful and
// where the focused application expects literal ASCII/navigation input. The
// text service uses the scope metadata only; it never reads the field value.
constexpr bool IsEnglishContext(InputScope scope) noexcept {
  switch (scope) {
    case IS_URL:
    case IS_FILE_FULLFILEPATH:
    case IS_FILE_FILENAME:
    case IS_EMAIL_USERNAME:
    case IS_EMAIL_SMTPEMAILADDRESS:
    case IS_LOGINNAME:
    case IS_DIGITS:
    case IS_NUMBER:
    case IS_ONECHAR:
    case IS_PASSWORD:
    case IS_TELEPHONE_FULLTELEPHONENUMBER:
    case IS_TELEPHONE_COUNTRYCODE:
    case IS_TELEPHONE_AREACODE:
    case IS_TELEPHONE_LOCALNUMBER:
    case IS_NUMBER_FULLWIDTH:
    case IS_ALPHANUMERIC_HALFWIDTH:
    case IS_ALPHANUMERIC_FULLWIDTH:
    case IS_NUMERIC_PASSWORD:
    case IS_NUMERIC_PIN:
    case IS_ALPHANUMERIC_PIN:
    case IS_ALPHANUMERIC_PIN_SET:
      return true;
    default:
      return false;
  }
}

// Kept as a compatibility name for the capture policy and existing smoke
// tests. "Direct" means the effective GY mode is temporary English and the
// target application receives literal keys; it does not mean the field text
// is inspected or copied.
constexpr bool IsDirectInput(InputScope scope) noexcept {
  return IsEnglishContext(scope);
}

constexpr bool IsPasswordContext(InputScope scope) noexcept {
  return scope == IS_PASSWORD || scope == IS_NUMERIC_PASSWORD ||
         scope == IS_NUMERIC_PIN || scope == IS_ALPHANUMERIC_PIN ||
         scope == IS_ALPHANUMERIC_PIN_SET;
}

// Passwords and PINs are a hard privacy boundary. Unlike a URL or email
// field, they cannot be temporarily switched back to Chinese composition by
// the GY mode shortcut while they have focus.
constexpr bool IsSensitiveDirectInput(InputScope scope) noexcept {
  return IsPasswordContext(scope);
}

constexpr bool AllowsManualChineseOverride(bool direct, bool sensitive) noexcept {
  return direct && !sensitive;
}

// The temporary Shift override belongs to one semantic field, never to an
// entire browser window. A tab can keep the same HWND and TSF context while
// focus moves from an email field to a password field, so the override must
// be cleared whenever the field classification changes.
constexpr bool ShouldClearManualChineseOverrideOnScopeChange(bool previous_known,
                                                              bool previous_direct,
                                                              bool previous_sensitive,
                                                              bool next_known,
                                                              bool next_direct,
                                                              bool next_sensitive) noexcept {
  return previous_known != next_known || previous_direct != next_direct ||
         previous_sensitive != next_sensitive;
}

// Browsers and Electron controls do not always publish a TSF InputScope.  In
// that case GY may use *accessibility metadata only* (label, automation ID or
// help text) to recognise the small set of fields that require literal input.
// It never reads a field's value, selection, clipboard or surrounding text.
// Keep the list deliberately narrow: a generic search/chat editor must remain
// Chinese-capable even when its window happens to contain English UI text.
inline bool IsEnglishAutomationHint(std::wstring_view hint) noexcept {
  auto contains_ascii = [hint](std::wstring_view token) {
    if (token.empty() || token.size() > hint.size()) return false;
    for (size_t start = 0; start + token.size() <= hint.size(); ++start) {
      bool match = true;
      for (size_t index = 0; index < token.size(); ++index) {
        wchar_t value = hint[start + index];
        if (value >= L'A' && value <= L'Z') value = static_cast<wchar_t>(value - L'A' + L'a');
        if (value != token[index]) { match = false; break; }
      }
      if (match) return true;
    }
    return false;
  };
  for (const std::wstring_view token : {
           L"email", L"e-mail", L"url", L"uri", L"website", L"password", L"passwd", L"pwd",
            L"pin", L"otp", L"one-time", L"verification", L"security code", L"username", L"login",
            L"telephone", L"phone"}) {
    if (contains_ascii(token)) return true;
  }
  for (const std::wstring_view token : {
           L"邮箱", L"邮件", L"网址", L"链接", L"密码", L"验证码", L"校验码", L"动态码",
            L"一次性", L"手机", L"电话", L"用户名", L"登录名"}) {
    if (hint.find(token) != std::wstring_view::npos) return true;
  }
  return false;
}

// Accessibility labels are metadata rather than typed text. Keep the hard
// privacy subset narrower than the broader literal-input classifier so an
// email or URL field can still use the temporary current-field Chinese
// override when the user deliberately asks for it.
inline bool IsSensitiveAutomationHint(std::wstring_view hint) noexcept {
  auto contains_ascii = [hint](std::wstring_view token) {
    if (token.empty() || token.size() > hint.size()) return false;
    for (size_t start = 0; start + token.size() <= hint.size(); ++start) {
      bool match = true;
      for (size_t index = 0; index < token.size(); ++index) {
        wchar_t value = hint[start + index];
        if (value >= L'A' && value <= L'Z') value = static_cast<wchar_t>(value - L'A' + L'a');
        if (value != token[index]) { match = false; break; }
      }
      if (match) return true;
    }
    return false;
  };
  for (const std::wstring_view token : {
           L"password", L"passwd", L"pwd", L"pin", L"otp", L"one-time",
           L"verification", L"security code"}) {
    if (contains_ascii(token)) return true;
  }
  for (const std::wstring_view token : {
           L"密码", L"验证码", L"校验码", L"动态码", L"一次性"}) {
    if (hint.find(token) != std::wstring_view::npos) return true;
  }
  return false;
}

}  // namespace gy::input_scope
