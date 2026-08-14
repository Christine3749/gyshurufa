#include "CandidateAppearancePolicy.h"

int main() {
  using gy::candidate_appearance::DisplayEvidence;
  static_assert(gy::candidate_appearance::NormalizeScalePreference(0) ==
                gy::candidate_appearance::ScalePreference::Auto);
  static_assert(gy::candidate_appearance::NormalizeScalePreference(95) ==
                gy::candidate_appearance::ScalePreference::Compact);
  static_assert(gy::candidate_appearance::NormalizeScalePreference(100) ==
                gy::candidate_appearance::ScalePreference::Standard);
  constexpr DisplayEvidence thinkpad_14{302, 189, 2560, 1600};
  constexpr DisplayEvidence desktop_27{597, 334, 3840, 2160};
  constexpr DisplayEvidence unknown_display{0, 0, 2560, 1600};
  constexpr DisplayEvidence invented_ratio{600, 340, 1280, 1024};
  static_assert(gy::candidate_appearance::HasReliablePhysicalSize(thinkpad_14));
  static_assert(gy::candidate_appearance::HasReliablePhysicalSize(desktop_27));
  static_assert(!gy::candidate_appearance::HasReliablePhysicalSize(unknown_display));
  static_assert(!gy::candidate_appearance::HasReliablePhysicalSize(invented_ratio));
  static_assert(gy::candidate_appearance::ResolveScalePercent(0, thinkpad_14) == 95);
  static_assert(gy::candidate_appearance::ResolveScalePercent(0, desktop_27) == 100);
  static_assert(gy::candidate_appearance::ResolveScalePercent(0, unknown_display) == 100);
  static_assert(gy::candidate_appearance::ResolveScalePercent(95, desktop_27) == 95);
  static_assert(gy::candidate_appearance::ResolveScalePercent(100, thinkpad_14) == 100);
  static_assert(gy::candidate_appearance::NormalizeScalePercent(95) == 95);
  static_assert(gy::candidate_appearance::NormalizeScalePercent(97) == 95);
  static_assert(gy::candidate_appearance::NormalizeScalePercent(98) == 100);
  static_assert(gy::candidate_appearance::NormalizeScalePercent(100) == 100);
  static_assert(gy::candidate_appearance::TypographyScalePercent(95) == 100);
  static_assert(gy::candidate_appearance::DetailScalePercent(95) == 100);
  static_assert(gy::candidate_appearance::VerticalScalePercent(95) == 99);
  static_assert(gy::candidate_appearance::VerticalScalePercent(100) == 100);
  static_assert(gy::candidate_appearance::ChineseNumberGutterDips(95) == 24);
  static_assert(gy::candidate_appearance::ChineseNumberGutterDips(100) == 24);
  static_assert(gy::candidate_appearance::ChineseCompactInsetsDips(95) == 8);
  static_assert(gy::candidate_appearance::EnglishWordLeftDips(95) == 11);
  static_assert(gy::candidate_appearance::EnglishWordRightDips(95) == 12);
  static_assert(gy::candidate_appearance::ModeHorizontalInsetsDips(95) == 17);
  static_assert(gy::candidate_appearance::DisclosureWidthDips(95) == 23);
  return 0;
}
