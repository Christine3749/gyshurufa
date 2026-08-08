#import <XCTest/XCTest.h>
#import "GYCandidateGovernance.h"

// Coverage for the exactCount boundary GYCandidateGovernance now threads
// through into GYCandidateSelection.directFallback — added alongside the
// gei -> ge fallback fix. A directFallback candidate's rimeDisplayIndex
// belongs to a DIFFERENT Rime session state than the one active at commit
// time (GYInputController -commitCandidateSelectionAtIndex:suffix:client:
// must bypass GYRimeBridge -commitCandidateAtAbsoluteIndex: for it, the
// same way it already does for local phrases), so mislabeling this
// boundary would commit the wrong candidate text.
@interface GYCandidateGovernanceTests : XCTestCase
@end

@implementation GYCandidateGovernanceTests

- (void)testAllExactWhenExactCountCoversWholeArray {
  NSArray<NSString *> *rime = @[@"给", @"歌", @"个"];
  NSArray<GYCandidateSelection *> *selections =
      [GYCandidateGovernance selectionsForRimeCandidates:rime customPhrases:@[] exactCount:rime.count];
  for (GYCandidateSelection *selection in selections) {
    XCTAssertFalse(selection.isDirectFallback);
  }
}

- (void)testEntriesAtOrBeyondExactCountAreMarkedFallback {
  NSArray<NSString *> *rime = @[@"给", @"歌", @"个", @"哥"];  // exact: 给 ; fallback: 歌 个 哥
  NSArray<GYCandidateSelection *> *selections =
      [GYCandidateGovernance selectionsForRimeCandidates:rime customPhrases:@[] exactCount:1];
  XCTAssertEqual(selections.count, (NSUInteger)4);
  XCTAssertFalse(selections[0].isDirectFallback, @"the one exact candidate must not be marked fallback");
  XCTAssertTrue(selections[1].isDirectFallback);
  XCTAssertTrue(selections[2].isDirectFallback);
  XCTAssertTrue(selections[3].isDirectFallback);
}

- (void)testFallbackFlagSurvivesDeduplication {
  // If a duplicate candidate is dropped, rimeDisplayIndex (and therefore the
  // fallback boundary check, which compares against the raw source-array
  // index) must still be computed from the ORIGINAL array position, not
  // the post-dedup output position.
  NSArray<NSString *> *rime = @[@"给", @"给", @"歌"];  // duplicate 给 at index 1 is dropped
  NSArray<GYCandidateSelection *> *selections =
      [GYCandidateGovernance selectionsForRimeCandidates:rime customPhrases:@[] exactCount:2];
  XCTAssertEqual(selections.count, (NSUInteger)2);
  XCTAssertEqualObjects(selections[0].text, @"给");
  XCTAssertFalse(selections[0].isDirectFallback, @"index 0 is within exactCount=2");
  XCTAssertEqualObjects(selections[1].text, @"歌");
  XCTAssertTrue(selections[1].isDirectFallback, @"歌 is at raw index 2, at/beyond exactCount=2");
}

- (void)testLocalPhrasesAreNeverMarkedFallback {
  NSArray<NSString *> *rime = @[@"给"];
  NSArray<GYCandidateSelection *> *selections =
      [GYCandidateGovernance selectionsForRimeCandidates:rime customPhrases:@[@"我的短语"] exactCount:0];
  GYCandidateSelection *phrase = selections.firstObject;
  XCTAssertEqualObjects(phrase.text, @"我的短语");
  XCTAssertTrue(phrase.isLocalPhrase);
  XCTAssertFalse(phrase.isDirectFallback, @"a local phrase is its own bypass category, not a Rime fallback");
}

- (void)testZeroExactCountMarksEverythingFallback {
  // The degenerate case: the exact composition produced nothing at all and
  // the entire pool came from fallback queries.
  NSArray<NSString *> *rime = @[@"歌", @"个"];
  NSArray<GYCandidateSelection *> *selections =
      [GYCandidateGovernance selectionsForRimeCandidates:rime customPhrases:@[] exactCount:0];
  for (GYCandidateSelection *selection in selections) {
    XCTAssertTrue(selection.isDirectFallback);
  }
}

@end
