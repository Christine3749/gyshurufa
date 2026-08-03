#include "CandidateLayout.h"


int main() {
  constexpr int kPadding = 10;
  constexpr int kCellWidth = 120;
  constexpr int kGap = 4;
  constexpr unsigned kColumns = gy::candidate_layout::ExpandedColumns();

  constexpr int grid_right = gy::candidate_layout::GridRight(kPadding, kCellWidth, kGap, kColumns);
  constexpr int fifth_column_right = kPadding + static_cast<int>(kColumns) * kCellWidth +
                                     static_cast<int>(kColumns - 1) * kGap;
  static_assert(grid_right == fifth_column_right);
  static_assert(gy::candidate_layout::GridRight(kPadding, kCellWidth, kGap, 0) == kPadding);

  static_assert(kColumns == 5);
  static_assert(gy::candidate_layout::ExpandedRows(6) == 2);
  static_assert(gy::candidate_layout::ExpandedRows(20) == 4);
  static_assert(gy::candidate_layout::ExpandedRows(25) == 5);
  static_assert(gy::candidate_layout::ExpandedRows(26) == 5);

  static_assert(gy::candidate_layout::ExpandedCapacity() == 25);
  static_assert(gy::candidate_layout::MoveExpandedDown(1, 0, 25) == 6);
  static_assert(gy::candidate_layout::MoveExpandedDown(21, 0, 25) == 21);
  static_assert(gy::candidate_layout::MoveExpandedDown(21, 0, 75) == 26);
  static_assert(gy::candidate_layout::MoveExpandedDown(24, 0, 75) == 29);
  static_assert(gy::candidate_layout::MoveExpandedDown(46, 25, 70) == 51);
  static_assert(gy::candidate_layout::MoveExpandedDown(66, 50, 70) == 66);
  static_assert(gy::candidate_layout::MoveExpandedUp(26, 25, 75) == 21);
  static_assert(gy::candidate_layout::MoveExpandedUp(29, 25, 75) == 24);
  static_assert(gy::candidate_layout::MoveExpandedUp(51, 50, 70) == 46);
  static_assert(gy::candidate_layout::MoveExpandedUp(1, 0, 75) == 1);
  static_assert(gy::candidate_layout::MoveExpandedLeft(6, 0, 25) == 5);
  static_assert(gy::candidate_layout::MoveExpandedLeft(5, 0, 25) == 5);
  static_assert(gy::candidate_layout::MoveExpandedRight(6, 0, 25) == 7);
  static_assert(gy::candidate_layout::MoveExpandedRight(9, 0, 25) == 9);
  static_assert(gy::candidate_layout::MoveExpandedDown(8, 0, 10) == 8);
  static_assert(grid_right >= fifth_column_right);
  static_assert(gy::candidate_layout::GridRight(kPadding, kCellWidth, kGap, 3) < grid_right);
  return 0;
}
