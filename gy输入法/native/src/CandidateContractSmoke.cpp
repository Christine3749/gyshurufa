#include "CandidateWindow.h"

#include <iostream>

// This is intentionally a product contract, not a responsive-layout heuristic.
// Altering these values requires an explicit reviewed revision of the GY
// candidate UX contract; normal releases must not silently change it.
int main() {
  static_assert(CandidateWindow::kCandidatesPerPage == 5);
  static_assert(CandidateWindow::kExpandedColumns == 5);
  static_assert(CandidateWindow::kExpandedMaxRows == 5);

  constexpr unsigned kExpandedCapacity =
      CandidateWindow::kExpandedColumns * CandidateWindow::kExpandedMaxRows;
  static_assert(kExpandedCapacity == 25, "GY candidate UX contract requires expanded 5x5.");
  return 0;
}
