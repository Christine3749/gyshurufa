#include "CandidatePresentationPolicy.h"

using gy::candidate_presentation::Surface;
using gy::candidate_presentation::Purpose;

int main() {
  static_assert(gy::candidate_presentation::Resolve(Purpose::ChineseConversion, false, 75) == Surface::ChineseStrip);
  static_assert(gy::candidate_presentation::Resolve(Purpose::ChineseConversion, true, 75) == Surface::ChineseGrid);
  static_assert(gy::candidate_presentation::Resolve(Purpose::EnglishCompletion, false, 75) == Surface::EnglishStrip);
  static_assert(gy::candidate_presentation::Resolve(Purpose::EnglishCompletion, true, 75) == Surface::EnglishStrip);
  static_assert(gy::candidate_presentation::Resolve(Purpose::EnglishCompletion, false, 75, false, true) ==
      Surface::EnglishList);
  static_assert(gy::candidate_presentation::Resolve(Purpose::EnglishCorrection, true, 5) ==
      Surface::EnglishStrip);

  // Five or fewer real candidates never create an empty expanded surface.
  static_assert(gy::candidate_presentation::Resolve(Purpose::ChineseConversion, true, 5) == Surface::ChineseStrip);
  static_assert(gy::candidate_presentation::Resolve(Purpose::EnglishCompletion, true, 5) == Surface::EnglishStrip);

  static_assert(gy::candidate_presentation::PageSize(Surface::ChineseStrip) == 5);
  static_assert(gy::candidate_presentation::PageSize(Surface::ChineseGrid) == 25);
  static_assert(gy::candidate_presentation::PageSize(Surface::EnglishStrip) == 5);
  static_assert(gy::candidate_presentation::PageSize(Surface::EnglishList) == 8);
  static_assert(gy::candidate_presentation::Columns(Surface::ChineseGrid) == 5);
  static_assert(gy::candidate_presentation::Columns(Surface::EnglishStrip) == 5);
  static_assert(gy::candidate_presentation::Columns(Surface::EnglishList) == 1);

  static_assert(gy::candidate_presentation::UsesNumericShortcuts(Surface::ChineseStrip));
  static_assert(gy::candidate_presentation::UsesNumericShortcuts(Surface::ChineseGrid));
  static_assert(!gy::candidate_presentation::UsesNumericShortcuts(Surface::EnglishStrip));
  static_assert(gy::candidate_presentation::CanExpand(Purpose::ChineseConversion, 6));
  static_assert(!gy::candidate_presentation::CanExpand(Purpose::EnglishCompletion, 75));
  static_assert(gy::candidate_presentation::CanExpandEnglish(Purpose::EnglishCompletion, 75));
  static_assert(gy::candidate_presentation::CanExpandEnglish(Purpose::EnglishCorrection, 75));
  static_assert(!gy::candidate_presentation::IsExpanded(Surface::EnglishStrip));
  static_assert(gy::candidate_presentation::IsExpanded(Surface::EnglishList));
  static_assert(gy::candidate_presentation::Resolve(Purpose::EnglishCompletion, true, 6) ==
      Surface::EnglishStrip);
  return 0;
}
