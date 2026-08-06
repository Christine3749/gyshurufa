#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Pure, byte-for-byte ports of native/src/CandidateLayout.h and the collapsed-
// strip math in native/src/GyIme.cpp's MoveSelection/MovePage. Kept dependency-
// free (no IMKit, no AppKit) so both GYInputController/GYCandidateWindow and
// the GYInputTests target can share and directly unit-test this logic instead
// of two independently hand-rolled copies drifting apart.

static const NSUInteger kGYCollapsedPageSize = 5;
static const NSUInteger kGYExpandedPageSize = 25;

// remaining-aware end of the current expanded page: page_start + min(remaining, 25).
NS_INLINE NSUInteger GYExpandedPageEnd(NSUInteger pageStart, NSUInteger candidateCount) {
  const NSUInteger remaining = candidateCount > pageStart ? candidateCount - pageStart : 0;
  return pageStart + MIN(remaining, kGYExpandedPageSize);
}

// ↓ in the fixed 5-wide grid: same column, next row; at the page's last row it
// crosses into the same column of the next 25-candidate page, clamped to the
// last real candidate if that page is shorter.
NS_INLINE NSUInteger GYMoveExpandedDown(NSUInteger selected, NSUInteger pageStart, NSUInteger candidateCount) {
  const NSUInteger pageEnd = GYExpandedPageEnd(pageStart, candidateCount);
  if (selected < pageStart || selected >= pageEnd) return pageStart;
  const NSUInteger next = selected + kGYCollapsedPageSize;
  if (next < pageEnd) return next;

  const NSUInteger nextPageStart = pageStart + kGYExpandedPageSize;
  if (nextPageStart >= candidateCount) return selected;
  const NSUInteger nextPageEnd = GYExpandedPageEnd(nextPageStart, candidateCount);
  const NSUInteger column = (selected - pageStart) % kGYCollapsedPageSize;
  const NSUInteger sameColumn = nextPageStart + column;
  return sameColumn < nextPageEnd ? sameColumn : nextPageEnd - 1;
}

// ↑ is the exact inverse of ↓, including the previous-page column crossing.
// Collapsing back to the single-row strip (page_start==0, row 0) is handled
// by the caller, matching Windows GyIme.cpp's VK_UP branch.
NS_INLINE NSUInteger GYMoveExpandedUp(NSUInteger selected, NSUInteger pageStart, NSUInteger candidateCount) {
  const NSUInteger pageEnd = GYExpandedPageEnd(pageStart, candidateCount);
  if (selected < pageStart || selected >= pageEnd) return pageStart;
  const NSUInteger offset = selected - pageStart;
  if (offset >= kGYCollapsedPageSize) return selected - kGYCollapsedPageSize;
  if (pageStart == 0) return selected;

  const NSUInteger previousPageStart = pageStart - kGYExpandedPageSize;
  const NSUInteger previousPageEnd = GYExpandedPageEnd(previousPageStart, candidateCount);
  const NSUInteger previousCount = previousPageEnd - previousPageStart;
  const NSUInteger lastRowStart = previousPageStart + ((previousCount - 1) / kGYCollapsedPageSize) * kGYCollapsedPageSize;
  const NSUInteger sameColumn = lastRowStart + offset;
  return sameColumn < previousPageEnd ? sameColumn : previousPageEnd - 1;
}

// ← / → never cross rows: at a row edge they hold still, exactly like
// Windows (no wraparound to the previous/next row).
NS_INLINE NSUInteger GYMoveExpandedLeft(NSUInteger selected, NSUInteger pageStart, NSUInteger candidateCount) {
  const NSUInteger pageEnd = GYExpandedPageEnd(pageStart, candidateCount);
  if (selected < pageStart || selected >= pageEnd) return pageStart;
  return (selected - pageStart) % kGYCollapsedPageSize == 0 ? selected : selected - 1;
}

NS_INLINE NSUInteger GYMoveExpandedRight(NSUInteger selected, NSUInteger pageStart, NSUInteger candidateCount) {
  const NSUInteger pageEnd = GYExpandedPageEnd(pageStart, candidateCount);
  if (selected < pageStart || selected >= pageEnd) return pageStart;
  const NSUInteger next = selected + 1;
  return (selected - pageStart) % kGYCollapsedPageSize == kGYCollapsedPageSize - 1 || next >= pageEnd
      ? selected
      : next;
}

// 1-5 digit keys in the expanded grid pick columns of the highlighted row.
// Returns candidateCount as an explicit invalid sentinel (matching Windows)
// when the column doesn't exist on a short final row.
NS_INLINE NSUInteger GYExpandedDigitCandidate(NSUInteger selected, NSUInteger pageStart,
                                              NSUInteger candidateCount, NSUInteger oneBasedColumn) {
  const NSUInteger pageEnd = GYExpandedPageEnd(pageStart, candidateCount);
  if (oneBasedColumn == 0 || oneBasedColumn > kGYCollapsedPageSize ||
      selected < pageStart || selected >= pageEnd) {
    return candidateCount;
  }
  const NSUInteger rowStart = pageStart + ((selected - pageStart) / kGYCollapsedPageSize) * kGYCollapsedPageSize;
  const NSUInteger candidate = rowStart + oneBasedColumn - 1;
  return candidate < pageEnd ? candidate : candidateCount;
}

// Collapsed-strip ← / →: move the highlight by one, wrapping across the
// whole fetched pool (matching Windows MoveSelection()).
NS_INLINE NSUInteger GYMoveCollapsedSelection(NSUInteger selected, NSInteger delta, NSUInteger candidateCount) {
  if (candidateCount == 0) return 0;
  NSInteger next = ((NSInteger)selected + delta) % (NSInteger)candidateCount;
  if (next < 0) next += (NSInteger)candidateCount;
  return (NSUInteger)next;
}

typedef struct {
  NSUInteger selected;
  NSUInteger pageStart;
  BOOL expanded;
} GYCandidateNavResult;

// Full ↑ transition, including the "first page, first row" collapse back to
// the single-row strip — selected_ is deliberately NOT reset there, matching
// Windows GyIme.cpp's VK_UP branch, so the user's highlight survives.
NS_INLINE GYCandidateNavResult GYExpandedUpTransition(NSUInteger selected, NSUInteger pageStart, NSUInteger candidateCount) {
  if (pageStart == 0 && selected < kGYCollapsedPageSize) {
    return (GYCandidateNavResult){
      .selected = selected,
      .pageStart = (selected / kGYCollapsedPageSize) * kGYCollapsedPageSize,
      .expanded = NO,
    };
  }
  const NSUInteger newSelected = GYMoveExpandedUp(selected, pageStart, candidateCount);
  return (GYCandidateNavResult){
    .selected = newSelected,
    .pageStart = (newSelected / kGYExpandedPageSize) * kGYExpandedPageSize,
    .expanded = YES,
  };
}

// Full ↓ transition in the expanded grid (↓ from the collapsed strip is a
// separate, unconditional "enter the grid" transition — see
// GYShouldEnterExpandedOnDown below).
NS_INLINE GYCandidateNavResult GYExpandedDownTransition(NSUInteger selected, NSUInteger pageStart, NSUInteger candidateCount) {
  const NSUInteger newSelected = GYMoveExpandedDown(selected, pageStart, candidateCount);
  return (GYCandidateNavResult){
    .selected = newSelected,
    .pageStart = (newSelected / kGYExpandedPageSize) * kGYExpandedPageSize,
    .expanded = YES,
  };
}

// Collapsed-strip ↓ always enters the grid regardless of candidate count (1-5
// candidates included) — matching Windows, which never guards this on count.
NS_INLINE BOOL GYShouldEnterExpandedOnDown(NSUInteger candidateCount) {
  return candidateCount > 0;
}

// PageUp/PageDown flip a whole 25-candidate page in the grid, but only a
// 5-candidate row in the collapsed strip — matching Windows
// PageSizeForCurrentView().
NS_INLINE NSUInteger GYPageSizeForState(BOOL expanded) {
  return expanded ? kGYExpandedPageSize : kGYCollapsedPageSize;
}

typedef struct {
  NSUInteger pageStart;
  NSUInteger selected;
} GYPageMoveResult;

// PageUp/PageDown, byte-for-byte ported from Windows GyIme.cpp's MovePage():
// a pure clamp to [0, last_page] within the already-fetched candidate pool.
// Windows never re-queries the engine here — the up-to-75 pool is fetched
// once (candidatesUpToCount:/PinyinEngine's kCandidatePoolLimit) and all
// paging after that is local index arithmetic. selected_ always lands on the
// target page's first candidate.
NS_INLINE GYPageMoveResult GYMovePageTransition(NSUInteger pageStart, NSInteger delta,
                                                 NSUInteger pageSize, NSUInteger candidateCount) {
  if (candidateCount == 0) return (GYPageMoveResult){.pageStart = pageStart, .selected = pageStart};
  pageSize = MAX((NSUInteger)1, pageSize);
  const NSInteger lastPage = (NSInteger)((candidateCount - 1) / pageSize);
  const NSInteger currentPage = (NSInteger)(pageStart / pageSize);
  NSInteger targetPage = currentPage + delta;
  if (targetPage < 0) targetPage = 0;
  if (targetPage > lastPage) targetPage = lastPage;
  const NSUInteger newPageStart = (NSUInteger)targetPage * pageSize;
  return (GYPageMoveResult){.pageStart = newPageStart, .selected = newPageStart};
}

// The right edge of a fixed grid must come from the grid geometry itself,
// never from whichever candidate happens to be last on a short final page —
// matching Windows CandidateLayout::GridRight exactly.
NS_INLINE CGFloat GYExpandedGridRight(CGFloat padding, CGFloat cellWidth, CGFloat gap, NSUInteger columns) {
  if (columns == 0) return padding;
  return padding + (CGFloat)columns * cellWidth + (CGFloat)(columns - 1) * gap;
}

NS_ASSUME_NONNULL_END
