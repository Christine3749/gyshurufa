#pragma once

namespace gy::candidate_layout {

// Candidate-grid geometry is a product contract. Keep this independent from
// the number of candidates on the current page: six real candidates render as
// 5 + 1, not as a responsive three-column panel.
constexpr unsigned ExpandedColumns() noexcept { return 5; }

constexpr unsigned ExpandedRows(unsigned candidate_count,
                                unsigned max_rows = 5) noexcept {
  constexpr unsigned kColumns = ExpandedColumns();
  if (candidate_count == 0 || max_rows == 0) return 0;
  const unsigned rows = (candidate_count + kColumns - 1) / kColumns;
  return rows < max_rows ? rows : max_rows;
}

constexpr unsigned ExpandedCapacity() noexcept { return ExpandedColumns() * 5; }

constexpr unsigned ExpandedPageEnd(unsigned page_start, unsigned candidate_count) noexcept {
  const unsigned remaining = candidate_count > page_start ? candidate_count - page_start : 0;
  return page_start + (remaining < ExpandedCapacity() ? remaining : ExpandedCapacity());
}

// In the expanded grid the number row follows the currently highlighted
// visual row. For example, with item 13 highlighted, key 1 selects item 11
// and key 5 selects item 15. Returning candidate_count is an explicit
// invalid sentinel for a missing cell in a partial final row.
constexpr unsigned ExpandedDigitCandidate(unsigned selected, unsigned page_start,
                                          unsigned candidate_count,
                                          unsigned one_based_column) noexcept {
  const unsigned page_end = ExpandedPageEnd(page_start, candidate_count);
  if (one_based_column == 0 || one_based_column > ExpandedColumns() ||
      selected < page_start || selected >= page_end) {
    return candidate_count;
  }
  const unsigned row_start = page_start +
      ((selected - page_start) / ExpandedColumns()) * ExpandedColumns();
  const unsigned candidate = row_start + one_based_column - 1;
  return candidate < page_end ? candidate : candidate_count;
}

// Keyboard movement follows the visual five-column grid. When ↓ reaches the
// last visible row it continues on the next 5 × 5 page in the same column;
// ↑ performs the exact inverse. PageUp/PageDown remain explicit full-page
// navigation keys.
constexpr unsigned MoveExpandedDown(unsigned selected, unsigned page_start, unsigned candidate_count) noexcept {
  const unsigned page_end = ExpandedPageEnd(page_start, candidate_count);
  if (selected < page_start || selected >= page_end) return page_start;
  const unsigned next = selected + ExpandedColumns();
  if (next < page_end) return next;

  const unsigned next_page_start = page_start + ExpandedCapacity();
  if (next_page_start >= candidate_count) return selected;
  const unsigned next_page_end = ExpandedPageEnd(next_page_start, candidate_count);
  const unsigned column = (selected - page_start) % ExpandedColumns();
  const unsigned same_column = next_page_start + column;
  return same_column < next_page_end ? same_column : next_page_end - 1;
}

constexpr unsigned MoveExpandedUp(unsigned selected, unsigned page_start, unsigned candidate_count) noexcept {
  const unsigned page_end = ExpandedPageEnd(page_start, candidate_count);
  if (selected < page_start || selected >= page_end) return page_start;
  const unsigned offset = selected - page_start;
  if (offset >= ExpandedColumns()) return selected - ExpandedColumns();
  if (page_start == 0) return selected;

  const unsigned previous_page_start = page_start - ExpandedCapacity();
  const unsigned previous_page_end = ExpandedPageEnd(previous_page_start, candidate_count);
  const unsigned previous_count = previous_page_end - previous_page_start;
  const unsigned last_row_start = previous_page_start +
      ((previous_count - 1) / ExpandedColumns()) * ExpandedColumns();
  const unsigned same_column = last_row_start + offset;
  return same_column < previous_page_end ? same_column : previous_page_end - 1;
}

constexpr unsigned MoveExpandedLeft(unsigned selected, unsigned page_start, unsigned candidate_count) noexcept {
  const unsigned page_end = ExpandedPageEnd(page_start, candidate_count);
  if (selected < page_start || selected >= page_end) return page_start;
  return (selected - page_start) % ExpandedColumns() == 0 ? selected : selected - 1;
}

constexpr unsigned MoveExpandedRight(unsigned selected, unsigned page_start, unsigned candidate_count) noexcept {
  const unsigned page_end = ExpandedPageEnd(page_start, candidate_count);
  if (selected < page_start || selected >= page_end) return page_start;
  const unsigned next = selected + 1;
  return (selected - page_start) % ExpandedColumns() == ExpandedColumns() - 1 || next >= page_end
      ? selected
      : next;
}
// The right edge of a fixed grid must be derived from the grid geometry, not
// from whichever candidate happens to be last on the current page.
constexpr int GridRight(int padding, int cell_width, int gap, unsigned columns) noexcept {
  if (columns == 0) return padding;
  return padding + static_cast<int>(columns) * cell_width +
         static_cast<int>(columns - 1) * gap;
}

}  // namespace gy::candidate_layout

