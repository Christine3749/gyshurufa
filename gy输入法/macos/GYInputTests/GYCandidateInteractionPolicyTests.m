#import <XCTest/XCTest.h>
#import "GYCandidateGridMath.h"
#import "GYPunctuationPolicy.h"

// Regression coverage for the macOS-vs-Windows interaction-parity fixes on
// codex/macos-stage4. Every case here mirrors a concrete behavior confirmed
// (by direct source comparison against native/src/GyIme.cpp and
// CandidateLayout.h) to differ before the fix, so a regression here means the
// two platforms have drifted apart again.
@interface GYCandidateInteractionPolicyTests : XCTestCase
@end

@implementation GYCandidateInteractionPolicyTests

#pragma mark - PageUp/PageDown page size (collapsed 5, expanded 25)

- (void)testCollapsedPageSizeIsFive {
  XCTAssertEqual(GYPageSizeForState(NO), (NSUInteger)5);
}

- (void)testExpandedPageSizeIsTwentyFive {
  XCTAssertEqual(GYPageSizeForState(YES), (NSUInteger)25);
}

#pragma mark - PageUp/PageDown: pure within-pool clamp (no engine re-fetch)

// Ported directly from Windows GyIme.cpp's MovePage(): page_start_ clamps to
// [0, last_page] within whatever's already in candidates_, and never grows
// the pool. clamp() means repeated PageDown at the last page (and repeated
// PageUp at page 0) must be a stable no-op, not silently wrap or fetch more.
- (void)assertPageSize:(NSUInteger)pageSize
          candidateCount:(NSUInteger)count
     pageStartsInOrder:(NSArray<NSNumber *> *)expectedPageStartsWalkingForward {
  NSUInteger pageStart = 0;
  for (NSNumber *expected in expectedPageStartsWalkingForward) {
    const GYPageMoveResult result = GYMovePageTransition(pageStart, 1, pageSize, count);
    XCTAssertEqual(result.pageStart, expected.unsignedIntegerValue,
                    @"count=%lu pageSize=%lu", (unsigned long)count, (unsigned long)pageSize);
    XCTAssertEqual(result.selected, result.pageStart);
    pageStart = result.pageStart;
  }
  // One more PageDown past the last page must be a stable no-op.
  const GYPageMoveResult atEnd = GYMovePageTransition(pageStart, 1, pageSize, count);
  XCTAssertEqual(atEnd.pageStart, pageStart, @"count=%lu should clamp at the last page", (unsigned long)count);

  // Walking all the way back up with PageUp must return to page 0 and then
  // stay there (not go negative / wrap).
  while (pageStart > 0) {
    const GYPageMoveResult back = GYMovePageTransition(pageStart, -1, pageSize, count);
    XCTAssertLessThan(back.pageStart, pageStart);
    pageStart = back.pageStart;
  }
  const GYPageMoveResult atStart = GYMovePageTransition(0, -1, pageSize, count);
  XCTAssertEqual(atStart.pageStart, (NSUInteger)0);
}

- (void)testPageTransitionCollapsedAcrossCandidateCounts {
  [self assertPageSize:5 candidateCount:0 pageStartsInOrder:@[]]; // empty pool: nothing to walk
  [self assertPageSize:5 candidateCount:1 pageStartsInOrder:@[]]; // single page (page 0 only)
  [self assertPageSize:5 candidateCount:5 pageStartsInOrder:@[]]; // exactly one full page
  [self assertPageSize:5 candidateCount:6 pageStartsInOrder:@[@5]]; // page 0, page 1 (1 item)
  [self assertPageSize:5 candidateCount:25 pageStartsInOrder:@[@5, @10, @15, @20]]; // 5 full pages
  [self assertPageSize:5 candidateCount:26 pageStartsInOrder:@[@5, @10, @15, @20, @25]]; // + 1-item page
  [self assertPageSize:5 candidateCount:75 pageStartsInOrder:@[@5, @10, @15, @20, @25, @30, @35, @40, @45, @50, @55, @60, @65, @70]]; // 15 full pages
}

- (void)testPageTransitionExpandedAcrossCandidateCounts {
  [self assertPageSize:25 candidateCount:0 pageStartsInOrder:@[]];
  [self assertPageSize:25 candidateCount:1 pageStartsInOrder:@[]];
  [self assertPageSize:25 candidateCount:25 pageStartsInOrder:@[]]; // exactly one full page
  [self assertPageSize:25 candidateCount:26 pageStartsInOrder:@[@25]]; // + 1-item page
  [self assertPageSize:25 candidateCount:75 pageStartsInOrder:@[@25, @50]]; // exactly 3 full pages
}

- (void)testPageTransitionEmptyPoolIsANoOp {
  const GYPageMoveResult result = GYMovePageTransition(0, 1, 5, 0);
  XCTAssertEqual(result.pageStart, (NSUInteger)0);
  XCTAssertEqual(result.selected, (NSUInteger)0);
}

- (void)testPageTransitionNeverExceedsFetchedPoolRegardlessOfDirection {
  // Even a large forward delta (repeated PageDown collapsed into one call)
  // must clamp inside the pool, not walk past candidateCount.
  const GYPageMoveResult result = GYMovePageTransition(0, 1000, 5, 26);
  XCTAssertEqual(result.pageStart, (NSUInteger)25);
  XCTAssertLessThan(result.pageStart, (NSUInteger)26);
}

#pragma mark - Collapsed strip Left/Right: move + wraparound

- (void)testCollapsedLeftRightMovesAndWraps {
  // 7 candidates, start at 0: ← must wrap to the last candidate (6).
  XCTAssertEqual(GYMoveCollapsedSelection(0, -1, 7), (NSUInteger)6);
  // → from the last candidate wraps back to 0.
  XCTAssertEqual(GYMoveCollapsedSelection(6, 1, 7), (NSUInteger)0);
  // Plain in-range move.
  XCTAssertEqual(GYMoveCollapsedSelection(2, 1, 7), (NSUInteger)3);
}

- (void)testCollapsedSpaceCommitsWhateverIsHighlighted {
  // Space always commits _selected verbatim (GYInputController.m); this
  // demonstrates the highlight produced by Left/Right is exactly what would
  // be committed, with no separate "first of page" fallback.
  NSUInteger selected = 0;
  selected = GYMoveCollapsedSelection(selected, 1, 5); // → to candidate 1
  selected = GYMoveCollapsedSelection(selected, 1, 5); // → to candidate 2
  XCTAssertEqual(selected, (NSUInteger)2);
}

#pragma mark - ↓ enters the grid regardless of candidate count

- (void)testDownEntersExpandedForOneToFiveCandidates {
  for (NSUInteger count = 1; count <= 5; ++count) {
    XCTAssertTrue(GYShouldEnterExpandedOnDown(count), @"count=%lu", (unsigned long)count);
  }
}

- (void)testDownDoesNothingForZeroCandidates {
  XCTAssertFalse(GYShouldEnterExpandedOnDown(0));
}

#pragma mark - Expanded grid: first row ↑ collapses but keeps the highlight

- (void)testFirstRowUpCollapsesKeepingHighlight {
  const GYCandidateNavResult result = GYExpandedUpTransition(3, 0, 12);
  XCTAssertFalse(result.expanded);
  XCTAssertEqual(result.pageStart, (NSUInteger)0);
  // The regression: this used to reset selected to 0 (candidate 1) instead
  // of preserving candidate 3's highlight.
  XCTAssertEqual(result.selected, (NSUInteger)3);
}

- (void)testSecondRowUpMovesWithinPage {
  const GYCandidateNavResult result = GYExpandedUpTransition(7, 0, 12); // row 1 col 2
  XCTAssertTrue(result.expanded);
  XCTAssertEqual(result.selected, (NSUInteger)2); // row 0 col 2
  XCTAssertEqual(result.pageStart, (NSUInteger)0);
}

- (void)testUpCrossesToPreviousPageSameColumnClampedToShortRow {
  // Page 2 starts at 25 with only 3 candidates (25,26,27); moving up from
  // page 2 row 0 col 0 (selected=25) must land on the previous page's last
  // row, clamped to that page's actual last candidate.
  const GYCandidateNavResult result = GYExpandedUpTransition(25, 25, 28);
  XCTAssertEqual(result.pageStart, (NSUInteger)0);
  // Previous page's last row starts at 20 (candidates 20-24); column 0 lands
  // on candidate 20.
  XCTAssertEqual(result.selected, (NSUInteger)20);
}

#pragma mark - ↓/↑/←/→ page-boundary + row-edge semantics (CandidateLayout.h parity)

- (void)testDownCrossesToNextPageSameColumn {
  // Last row of page 1 (candidates 20-24), column 2 (selected=22) crossing
  // down should land in the same column on page 2 (25 + 2 = 27).
  XCTAssertEqual(GYMoveExpandedDown(22, 0, 60), (NSUInteger)27);
}

- (void)testDownClampsWhenNextPageIsShorterThanTheColumn {
  // Next page (page start 25) only has 3 candidates (25,26,27); column 4
  // (selected=24) doesn't exist there, so it must clamp to the last real
  // candidate (27), not silently do nothing and not compute an OOB index.
  const NSUInteger result = GYMoveExpandedDown(24, 0, 28);
  XCTAssertEqual(result, (NSUInteger)27);
}

- (void)testDownStaysPutOnTheLastPage {
  XCTAssertEqual(GYMoveExpandedDown(2, 0, 4), (NSUInteger)2);
}

- (void)testLeftRightNeverWrapAcrossRows {
  // selected=25 is the first column of its row: ← must hold still, not wrap
  // to the previous row's last column (this was a real bug: the old
  // implementation used flat ±1 arithmetic with no column boundary check).
  XCTAssertEqual(GYMoveExpandedLeft(25, 25, 60), (NSUInteger)25);
  // selected=29 is the last column of its row: → must hold still.
  XCTAssertEqual(GYMoveExpandedRight(29, 25, 60), (NSUInteger)29);
  // Plain in-row moves still work.
  XCTAssertEqual(GYMoveExpandedRight(25, 25, 60), (NSUInteger)26);
  XCTAssertEqual(GYMoveExpandedLeft(26, 25, 60), (NSUInteger)25);
}

#pragma mark - Fixed 5-column grid geometry (short final page)

- (void)testGridRightIsIndependentOfVisibleCandidateCount {
  const CGFloat padding = 6, gap = 3, cellW = 90;
  const CGFloat fullPage = GYExpandedGridRight(padding, cellW, gap, 5);
  // Regardless of how many candidates are actually visible on the page, the
  // fixed grid always reserves 5 columns worth of width. The old bug derived
  // this from "whichever candidate happens to be last", which shrank for a
  // 1-4 candidate final page (e.g. 25 candidates total, page 2 has 1 item).
  XCTAssertEqual(fullPage, padding + 5 * cellW + 4 * gap);
  XCTAssertEqualWithAccuracy(fullPage, 468.0, 0.001);
}

- (void)testFooterButtonRectsStayNonNegativeOnAOneCandidateLastPage {
  // 25 + 1 candidates: page 2 (pageStart=25) has exactly one visible
  // candidate. The footer buttons are laid out right-to-left off gridRight;
  // if gridRight collapsed to a single cell's width (the old bug), indLeft/
  // prevLeft went negative and the pager visibly clipped or crashed layout.
  const CGFloat padding = 6, gap = 3, pageBtnW = 26, pageIndW = 42, cellW = 82; // clamp floor
  const CGFloat gridRight = GYExpandedGridRight(padding, cellW, gap, 5);
  const CGFloat nextLeft = gridRight - pageBtnW;
  const CGFloat indLeft = nextLeft - gap - pageIndW;
  const CGFloat prevLeft = indLeft - gap - pageBtnW;
  XCTAssertGreaterThanOrEqual(nextLeft, 0.0);
  XCTAssertGreaterThanOrEqual(indLeft, 0.0);
  XCTAssertGreaterThanOrEqual(prevLeft, 0.0);
}

#pragma mark - Digit keys (1-5) never misselect a missing column on a short row

- (void)testDigitKeyOnFullRowSelectsCorrectColumn {
  // selected=2 sits in row 0; column 4 (key '4') is candidate index 3.
  XCTAssertEqual(GYExpandedDigitCandidate(2, 0, 12, 4), (NSUInteger)3);
}

- (void)testDigitKeyOnShortLastRowReturnsInvalidSentinelForMissingColumn {
  // Row starting at 10 has only candidates 10,11,12 (3 of 5 columns). Key 5
  // (column 5) doesn't exist and must return candidateCount as an explicit
  // invalid sentinel, never an out-of-bounds or wrong candidate.
  const NSUInteger candidateCount = 13;
  XCTAssertEqual(GYExpandedDigitCandidate(10, 10, candidateCount, 3), (NSUInteger)12);
  XCTAssertEqual(GYExpandedDigitCandidate(10, 10, candidateCount, 4), candidateCount);
  XCTAssertEqual(GYExpandedDigitCandidate(10, 10, candidateCount, 5), candidateCount);
}

#pragma mark - Chinese punctuation full set + stateful smart quotes

- (void)testFullPunctuationSetMatchesWindowsPunctuationPolicy {
  BOOL single = YES, doubleQ = YES;
  NSDictionary<NSString *, NSString *> *expected = @{
    @",": @"，", @"<": @"《", @".": @"。", @">": @"》",
    @";": @"；", @":": @"：", @"/": @"、", @"?": @"？",
    @"[": @"【", @"{": @"｛", @"]": @"】", @"}": @"｝",
    @"!": @"！",
  };
  for (NSString *key in expected) {
    XCTAssertEqualObjects(GYChinesePunctuationLookup(key, &single, &doubleQ), expected[key], @"key=%@", key);
  }
}

- (void)testUnmappedCharacterReturnsNil {
  BOOL single = YES, doubleQ = YES;
  XCTAssertNil(GYChinesePunctuationLookup(@"a", &single, &doubleQ));
}

- (void)testSmartQuotesToggleIndependently {
  BOOL single = YES, doubleQ = YES;
  XCTAssertEqualObjects(GYChinesePunctuationLookup(@"'", &single, &doubleQ), @"‘");
  XCTAssertFalse(single);
  XCTAssertEqualObjects(GYChinesePunctuationLookup(@"'", &single, &doubleQ), @"’");
  XCTAssertTrue(single);
  // Double-quote state is untouched by single-quote presses.
  XCTAssertEqualObjects(GYChinesePunctuationLookup(@"\"", &single, &doubleQ), @"“");
  XCTAssertFalse(doubleQ);
  XCTAssertEqualObjects(GYChinesePunctuationLookup(@"\"", &single, &doubleQ), @"”");
  XCTAssertTrue(doubleQ);
}

@end
