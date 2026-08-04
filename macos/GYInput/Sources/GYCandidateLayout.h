#import <Foundation/Foundation.h>

typedef struct {
  NSUInteger pageStart;
  NSUInteger selection;
  BOOL expanded;
} GYCandidateLayout;

typedef NS_ENUM(NSUInteger, GYCandidateMovement) {
  GYCandidateMovementUp, GYCandidateMovementDown, GYCandidateMovementLeft,
  GYCandidateMovementRight, GYCandidateMovementPreviousPage, GYCandidateMovementNextPage,
};

static const NSUInteger GYCandidatePoolLimit = 75;
static const NSUInteger GYCandidateColumns = 5;
static const NSUInteger GYCandidateExpandedPageSize = 25;

static inline NSUInteger GYCandidatePageSize(BOOL expanded) {
  return expanded ? GYCandidateExpandedPageSize : GYCandidateColumns;
}

static inline NSUInteger GYCandidatePageEnd(GYCandidateLayout layout, NSUInteger count) {
  return MIN(layout.pageStart + GYCandidatePageSize(layout.expanded), count);
}

static inline NSUInteger GYCandidateVisibleCount(GYCandidateLayout layout, NSUInteger count) {
  return layout.pageStart < count ? GYCandidatePageEnd(layout, count) - layout.pageStart : 0;
}

FOUNDATION_EXPORT void GYNormalizeCandidateLayout(GYCandidateLayout *layout, NSUInteger count);
FOUNDATION_EXPORT void GYSetCandidateLayoutExpanded(GYCandidateLayout *layout, NSUInteger count, BOOL expanded);
FOUNDATION_EXPORT BOOL GYMoveCandidateLayout(GYCandidateLayout *layout, NSUInteger count,
                                              GYCandidateMovement movement);
FOUNDATION_EXPORT BOOL GYRunCandidateLayoutSelfTest(void);
