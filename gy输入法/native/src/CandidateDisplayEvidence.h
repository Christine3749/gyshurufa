#pragma once

#include "CandidateAppearancePolicy.h"

#include <windows.h>

namespace gy::candidate_appearance {

inline DisplayEvidence ReadDisplayEvidence(HMONITOR monitor) noexcept {
  DisplayEvidence result{};
  if (!monitor) return result;

  MONITORINFOEXW info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(monitor, &info)) return result;
  result.width_px = Positive(static_cast<int>(info.rcMonitor.right - info.rcMonitor.left));
  result.height_px = Positive(static_cast<int>(info.rcMonitor.bottom - info.rcMonitor.top));

  // A monitor-specific DC exposes the physical millimetres reported by the
  // display/driver.  The policy validates these values before trusting them.
  const HDC dc = CreateDCW(nullptr, info.szDevice, nullptr, nullptr);
  if (!dc) return result;
  result.width_mm = GetDeviceCaps(dc, HORZSIZE);
  result.height_mm = GetDeviceCaps(dc, VERTSIZE);
  DeleteDC(dc);
  return result;
}

inline int ResolveScalePercentForMonitor(int requested, HMONITOR monitor) noexcept {
  return ResolveScalePercent(requested, ReadDisplayEvidence(monitor));
}

}  // namespace gy::candidate_appearance
