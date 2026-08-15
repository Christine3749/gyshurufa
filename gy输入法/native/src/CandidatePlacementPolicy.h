#pragma once

#include <algorithm>

namespace gy::candidate_placement {

// Placement clearance belongs to the host application's text line, not to
// GY's visual scale. A 95% candidate surface must therefore keep the same
// text-safe anchor and outside gap as the 100% surface.
constexpr int kMinimumAnchorHeightDips = 24;
constexpr int kTextGapDips = 8;

struct Anchor {
  int left = 0;
  int top = 0;
  int right = 0;
  int bottom = 0;
};

constexpr Anchor NormalizeAnchor(int left, int top, int right, int bottom,
                                 int minimum_height) noexcept {
  Anchor anchor{
      std::min(left, right),
      std::min(top, bottom),
      std::max(left, right),
      std::max(top, bottom),
  };
  if (anchor.right <= anchor.left) anchor.right = anchor.left + 1;
  const int safe_height = std::max(1, minimum_height);
  if (anchor.bottom - anchor.top < safe_height) {
    anchor.bottom = anchor.top + safe_height;
  }
  return anchor;
}

enum class Side {
  Below,
  Above,
  BestEffortBelow,
  BestEffortAbove,
};

struct VerticalPlacement {
  int y = 0;
  Side side = Side::Below;
};

constexpr int Clamp(int value, int minimum, int maximum) noexcept {
  return std::min(std::max(value, minimum), std::max(minimum, maximum));
}

constexpr VerticalPlacement PlaceVertically(int work_top, int work_bottom,
                                             const Anchor& anchor,
                                             int window_height, int gap) noexcept {
  const int safe_height = std::max(1, window_height);
  const int safe_gap = std::max(0, gap);
  const int below = anchor.bottom + safe_gap;
  const int above = anchor.top - safe_gap - safe_height;

  if (below + safe_height <= work_bottom) return {below, Side::Below};
  if (above >= work_top) return {above, Side::Above};

  // An unusually tall expanded surface may fit neither side. Preserve as
  // much of the larger side as possible; compact rows always take one of the
  // two non-overlapping branches above on a normal Windows work area.
  const int room_below = work_bottom - below;
  const int room_above = anchor.top - safe_gap - work_top;
  if (room_below >= room_above) {
    return {Clamp(below, work_top, work_bottom - safe_height), Side::BestEffortBelow};
  }
  return {Clamp(above, work_top, work_bottom - safe_height), Side::BestEffortAbove};
}

constexpr bool Intersects(const Anchor& anchor, int window_y,
                          int window_height) noexcept {
  return window_y < anchor.bottom && window_y + window_height > anchor.top;
}

}  // namespace gy::candidate_placement
