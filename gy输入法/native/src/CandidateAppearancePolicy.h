#pragma once

namespace gy::candidate_appearance {

// 95% is a distinct optical composition, not a bitmap-like uniform shrink.
// The panel footprint becomes quieter on a laptop, while type, one-pixel
// strokes, corners and disclosure marks retain the authority of the 100%
// design. Horizontal rhythm carries the reduction; vertical rhythm remains
// intact so the strip never looks compressed.
constexpr int kCompactScalePercent = 95;
constexpr int kDefaultScalePercent = 100;
constexpr int kAutoScalePreference = 0;

enum class ScalePreference : int {
  Auto = kAutoScalePreference,
  Compact = kCompactScalePercent,
  Standard = kDefaultScalePercent,
};

struct DisplayEvidence {
  int width_mm = 0;
  int height_mm = 0;
  int width_px = 0;
  int height_px = 0;
};

constexpr ScalePreference NormalizeScalePreference(int requested) noexcept {
  if (requested == kCompactScalePercent) return ScalePreference::Compact;
  if (requested == kDefaultScalePercent) return ScalePreference::Standard;
  return ScalePreference::Auto;
}

constexpr int Positive(int value) noexcept { return value < 0 ? -value : value; }
constexpr int Smaller(int first, int second) noexcept { return first < second ? first : second; }
constexpr int Larger(int first, int second) noexcept { return first > second ? first : second; }

// A display driver can report invented physical dimensions.  Treat the value
// as evidence only when it is plausible and its aspect ratio broadly agrees
// with the active pixel rectangle.  Rotation is handled by comparing the
// shorter and longer sides rather than width to width.
constexpr bool HasReliablePhysicalSize(const DisplayEvidence& display) noexcept {
  const int short_mm = Smaller(display.width_mm, display.height_mm);
  const int long_mm = Larger(display.width_mm, display.height_mm);
  const int short_px = Smaller(display.width_px, display.height_px);
  const int long_px = Larger(display.width_px, display.height_px);
  if (short_mm < 80 || long_mm < 150 || long_mm > 2500 ||
      short_px < 480 || long_px < 640) return false;
  const long long millimetre_ratio = static_cast<long long>(long_mm) * short_px;
  const long long pixel_ratio = static_cast<long long>(short_mm) * long_px;
  const long long difference = millimetre_ratio > pixel_ratio
      ? millimetre_ratio - pixel_ratio : pixel_ratio - millimetre_ratio;
  return difference * 100 <= Larger(
      static_cast<int>(millimetre_ratio), static_cast<int>(pixel_ratio)) * 18LL;
}

constexpr int AutomaticScalePercent(const DisplayEvidence& display) noexcept {
  if (!HasReliablePhysicalSize(display)) return kDefaultScalePercent;
  // 18 inches is 457.2 mm.  This includes 13/14/15/16/17-inch notebooks,
  // while a desktop monitor remains on the 100% composition.
  constexpr int kCompactDiagonalMillimetres = 457;
  const long long diagonal_squared =
      static_cast<long long>(display.width_mm) * display.width_mm +
      static_cast<long long>(display.height_mm) * display.height_mm;
  return diagonal_squared <=
      static_cast<long long>(kCompactDiagonalMillimetres) * kCompactDiagonalMillimetres
      ? kCompactScalePercent : kDefaultScalePercent;
}

constexpr int ResolveScalePercent(int requested, const DisplayEvidence& display) noexcept {
  switch (NormalizeScalePreference(requested)) {
    case ScalePreference::Compact: return kCompactScalePercent;
    case ScalePreference::Standard: return kDefaultScalePercent;
    case ScalePreference::Auto: return AutomaticScalePercent(display);
  }
  return kDefaultScalePercent;
}

constexpr int NormalizeScalePercent(int requested) noexcept {
  return requested <= 97 ? kCompactScalePercent : kDefaultScalePercent;
}

constexpr bool IsCompact(int normalized_scale_percent) noexcept {
  return NormalizeScalePercent(normalized_scale_percent) == kCompactScalePercent;
}

constexpr int TypographyScalePercent(int) noexcept {
  return kDefaultScalePercent;
}

constexpr int DetailScalePercent(int) noexcept {
  return kDefaultScalePercent;
}

constexpr int VerticalScalePercent(int normalized_scale_percent) noexcept {
  return IsCompact(normalized_scale_percent) ? 99 : kDefaultScalePercent;
}

// Compact-only optical tokens. These are fed through the 95% surface scale,
// so their effective reduction is deliberately stronger than five percent.
// That recovered space lets typography stay full and crisp.
constexpr int ChineseNumberGutterDips(int) noexcept {
  return 24;
}

constexpr int ChineseCompactInsetsDips(int) noexcept {
  return 8;
}

constexpr int ChineseWordLeftDips(int normalized_scale_percent) noexcept {
  return IsCompact(normalized_scale_percent) ? 20 : 21;
}

constexpr int ChineseWordRightDips(int normalized_scale_percent) noexcept {
  return IsCompact(normalized_scale_percent) ? 4 : 5;
}

constexpr int EnglishWordLeftDips(int normalized_scale_percent) noexcept {
  return IsCompact(normalized_scale_percent) ? 11 : 12;
}

constexpr int EnglishWordRightDips(int) noexcept {
  return 12;
}

constexpr int ModeHorizontalInsetsDips(int normalized_scale_percent) noexcept {
  return IsCompact(normalized_scale_percent) ? 17 : 18;
}

constexpr int DisclosureWidthDips(int normalized_scale_percent) noexcept {
  return IsCompact(normalized_scale_percent) ? 23 : 24;
}

}  // namespace gy::candidate_appearance
