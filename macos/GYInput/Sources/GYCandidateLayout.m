#import "GYCandidateLayout.h"

void GYNormalizeCandidateLayout(GYCandidateLayout *layout, NSUInteger count) {
  if (layout == NULL || count == 0) { if (layout) *layout = (GYCandidateLayout){0}; return; }
  NSUInteger size = GYCandidatePageSize(layout->expanded);
  layout->pageStart = MIN(layout->pageStart / size * size, (count - 1) / size * size);
  layout->selection = MIN(layout->selection, GYCandidateVisibleCount(*layout, count) - 1);
}

void GYSetCandidateLayoutExpanded(GYCandidateLayout *layout, NSUInteger count, BOOL expanded) {
  if (layout == NULL) return;
  GYNormalizeCandidateLayout(layout, count);
  NSUInteger absolute = layout->pageStart + layout->selection;
  layout->expanded = expanded;
  NSUInteger size = GYCandidatePageSize(expanded);
  layout->pageStart = absolute / size * size;
  layout->selection = absolute - layout->pageStart;
  GYNormalizeCandidateLayout(layout, count);
}

static void GYMovePage(GYCandidateLayout *layout, NSUInteger count, NSInteger delta) {
  NSUInteger size = GYCandidatePageSize(layout->expanded);
  NSInteger target = (NSInteger)layout->pageStart + delta * (NSInteger)size;
  NSInteger maximum = (NSInteger)((count - 1) / size * size);
  layout->pageStart = (NSUInteger)MIN(MAX(target, 0), maximum);
  layout->selection = 0;
}

BOOL GYMoveCandidateLayout(GYCandidateLayout *layout, NSUInteger count, GYCandidateMovement movement) {
  if (layout == NULL || count == 0) return NO;
  GYNormalizeCandidateLayout(layout, count);
  if (!layout->expanded) {
    if (movement == GYCandidateMovementDown && count > GYCandidateColumns) {
      GYSetCandidateLayoutExpanded(layout, count, YES);
    } else if (movement == GYCandidateMovementPreviousPage) {
      GYMovePage(layout, count, -1);
    } else if (movement == GYCandidateMovementNextPage) {
      GYMovePage(layout, count, 1);
    } else if (movement == GYCandidateMovementLeft || movement == GYCandidateMovementRight) {
      NSInteger absolute = (NSInteger)layout->pageStart + layout->selection +
          (movement == GYCandidateMovementLeft ? -1 : 1);
      absolute = (absolute + (NSInteger)count) % (NSInteger)count;
      layout->pageStart = (NSUInteger)absolute / GYCandidateColumns * GYCandidateColumns;
      layout->selection = (NSUInteger)absolute - layout->pageStart;
    }
    return YES;
  }

  NSUInteger visible = GYCandidateVisibleCount(*layout, count);
  if (movement == GYCandidateMovementPreviousPage || movement == GYCandidateMovementNextPage) {
    GYMovePage(layout, count, movement == GYCandidateMovementPreviousPage ? -1 : 1);
  } else if (movement == GYCandidateMovementUp) {
    if (layout->pageStart == 0 && layout->selection < GYCandidateColumns) {
      GYSetCandidateLayoutExpanded(layout, count, NO);
    } else if (layout->selection >= GYCandidateColumns) {
      layout->selection -= GYCandidateColumns;
    } else {
      NSUInteger column = layout->selection;
      layout->pageStart -= GYCandidateExpandedPageSize;
      NSUInteger previous = GYCandidateVisibleCount(*layout, count);
      NSUInteger lastRow = (previous - 1) / GYCandidateColumns * GYCandidateColumns;
      layout->selection = MIN(lastRow + column, previous - 1);
    }
  } else if (movement == GYCandidateMovementDown) {
    NSUInteger next = layout->selection + GYCandidateColumns;
    if (next < visible) layout->selection = next;
    else if (layout->pageStart + GYCandidateExpandedPageSize < count) {
      NSUInteger column = layout->selection % GYCandidateColumns;
      layout->pageStart += GYCandidateExpandedPageSize;
      layout->selection = MIN(column, GYCandidateVisibleCount(*layout, count) - 1);
    }
  } else if (movement == GYCandidateMovementLeft) {
    if (layout->selection % GYCandidateColumns) layout->selection--;
  } else if (movement == GYCandidateMovementRight) {
    if (layout->selection % GYCandidateColumns != GYCandidateColumns - 1 && layout->selection + 1 < visible) layout->selection++;
  }
  return YES;
}

BOOL GYRunCandidateLayoutSelfTest(void) {
  GYCandidateLayout state = {0};
  if (!GYMoveCandidateLayout(&state, 75, GYCandidateMovementDown) || !state.expanded) return NO;
  state.selection = 24;
  GYMoveCandidateLayout(&state, 75, GYCandidateMovementDown);
  if (state.pageStart != 25 || state.selection != 4) return NO;
  GYMoveCandidateLayout(&state, 75, GYCandidateMovementUp);
  if (state.pageStart != 0 || state.selection != 24) return NO;
  state.selection = 0; GYMoveCandidateLayout(&state, 75, GYCandidateMovementLeft);
  if (state.selection != 0) return NO;
  state.selection = 4; GYMoveCandidateLayout(&state, 75, GYCandidateMovementRight);
  if (state.selection != 4) return NO;
  state.selection = 23; GYMoveCandidateLayout(&state, 26, GYCandidateMovementDown);
  if (state.pageStart != 25 || state.selection != 0) return NO;
  GYMoveCandidateLayout(&state, 26, GYCandidateMovementUp);
  if (state.pageStart != 0 || state.selection != 20) return NO;
  return GYCandidatePoolLimit == 75 && GYCandidateExpandedPageSize == 25;
}
