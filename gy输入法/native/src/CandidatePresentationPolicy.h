#pragma once

#include "CandidateLayout.h"
#include "EnglishCandidatePolicy.h"

namespace gy::candidate_presentation {

constexpr unsigned CompactCapacity() noexcept { return 5; }
constexpr unsigned EnglishCompactCapacity() noexcept {
  return gy::english_candidates::kCompactVisible;
}
constexpr unsigned EnglishExpandedCapacity() noexcept {
  return gy::english_candidates::kExpandedVisible;
}

// Purpose describes why candidates exist. Input mode still controls language
// and punctuation, but it no longer doubles as a rendering instruction.
enum class Purpose : unsigned {
  ChineseConversion = 0,
  EnglishCompletion = 1,
  EnglishCorrection = 2,
};

constexpr Purpose NormalizePurpose(unsigned value) noexcept {
  return value <= static_cast<unsigned>(Purpose::EnglishCorrection)
      ? static_cast<Purpose>(value) : Purpose::ChineseConversion;
}

enum class Surface {
  ModeBadge,
  ChineseStrip,
  ChineseGrid,
  EnglishStrip,
  EnglishList,
};

constexpr bool CanExpand(Purpose purpose, unsigned candidate_count) noexcept {
  return purpose == Purpose::ChineseConversion && candidate_count > CompactCapacity();
}

constexpr bool CanExpandEnglish(Purpose purpose, unsigned candidate_count) noexcept {
  return (purpose == Purpose::EnglishCompletion || purpose == Purpose::EnglishCorrection) &&
      candidate_count > EnglishCompactCapacity();
}

constexpr Surface Resolve(Purpose purpose, bool request_chinese_grid,
                          unsigned candidate_count, bool mode_popup = false,
                          bool request_english_list = false) noexcept {
  if (mode_popup) return Surface::ModeBadge;
  const bool chinese_grid_open = request_chinese_grid && CanExpand(purpose, candidate_count);
  if (purpose == Purpose::EnglishCompletion || purpose == Purpose::EnglishCorrection) {
    return request_english_list && CanExpandEnglish(purpose, candidate_count)
        ? Surface::EnglishList : Surface::EnglishStrip;
  }
  return chinese_grid_open ? Surface::ChineseGrid : Surface::ChineseStrip;
}

constexpr bool IsExpanded(Surface surface) noexcept {
  return surface == Surface::ChineseGrid || surface == Surface::EnglishList;
}

constexpr bool IsChineseGrid(Surface surface) noexcept {
  return surface == Surface::ChineseGrid;
}

constexpr bool IsEnglish(Surface surface) noexcept {
  return surface == Surface::EnglishStrip || surface == Surface::EnglishList;
}

constexpr bool IsEnglishList(Surface surface) noexcept {
  return surface == Surface::EnglishList;
}

constexpr bool UsesNumericShortcuts(Surface surface) noexcept {
  return surface == Surface::ChineseStrip || surface == Surface::ChineseGrid;
}

constexpr unsigned PageSize(Surface surface) noexcept {
  if (surface == Surface::ChineseGrid) return gy::candidate_layout::ExpandedCapacity();
  if (surface == Surface::EnglishList) return EnglishExpandedCapacity();
  return surface == Surface::EnglishStrip ? EnglishCompactCapacity() : CompactCapacity();
}

constexpr unsigned Columns(Surface surface) noexcept {
  if (surface == Surface::ChineseGrid) return gy::candidate_layout::ExpandedColumns();
  if (surface == Surface::EnglishList) return 1;
  return surface == Surface::EnglishStrip ? EnglishCompactCapacity() : CompactCapacity();
}

}  // namespace gy::candidate_presentation
