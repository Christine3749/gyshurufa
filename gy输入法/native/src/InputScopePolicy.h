#pragma once

#include <inputscope.h>

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

}  // namespace gy::input_scope
