#include "CandidatePlacementPolicy.h"

int main() {
  using gy::candidate_placement::Intersects;
  using gy::candidate_placement::NormalizeAnchor;
  using gy::candidate_placement::PlaceVertically;
  using gy::candidate_placement::Side;

  // Some custom editors report an insertion point rather than a text-height
  // rectangle. It still receives a full protected line before the popup.
  constexpr auto point = NormalizeAnchor(400, 100, 400, 100, 24);
  static_assert(point.left == 400 && point.right == 401);
  static_assert(point.top == 100 && point.bottom == 124);
  constexpr auto below = PlaceVertically(0, 900, point, 60, 8);
  static_assert(below.side == Side::Below && below.y == 132);
  static_assert(!Intersects(point, below.y, 60));

  // Near the taskbar, the complete candidate row moves above the input line
  // instead of being clamped back across the text.
  constexpr auto bottom_caret = NormalizeAnchor(300, 850, 302, 874, 24);
  constexpr auto above = PlaceVertically(0, 900, bottom_caret, 80, 8);
  static_assert(above.side == Side::Above && above.y == 762);
  static_assert(!Intersects(bottom_caret, above.y, 80));

  // An already valid application rectangle is preserved exactly.
  constexpr auto valid = NormalizeAnchor(20, 40, 120, 70, 24);
  static_assert(valid.left == 20 && valid.top == 40 && valid.right == 120 && valid.bottom == 70);
  return 0;
}
