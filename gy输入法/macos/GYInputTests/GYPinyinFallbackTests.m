#import <XCTest/XCTest.h>
#import "GYPinyinFallback.h"

// Regression coverage for the review finding: Mac's candidate window only
// ever queried the exact pinyin composition, so "gei" (which luna_pinyin
// has very few exact matches for) showed one candidate and left the other
// 24 cells of the 5×5 grid empty — a real, user-visible break of the
// locked 5×5 product rule (spec §5.2), already fixed on Windows
// (PinyinEngine.cpp's Lookup()) and ported here.
@interface GYPinyinFallbackTests : XCTestCase
@end

@implementation GYPinyinFallbackTests

- (void)testDropsLastCharacter {
  XCTAssertEqualObjects(GYNextFallbackPinyinCode(@"gei"), @"ge");
}

- (void)testLowercasesInput {
  XCTAssertEqualObjects(GYNextFallbackPinyinCode(@"GEI"), @"ge");
}

- (void)testStopsAtTwoCharacters {
  // "ge" (2 chars) is still a usable fallback surface -- confirmed by
  // dropping from "gei" above -- but falling back FROM "ge" must refuse:
  // a bare single letter is too noisy.
  XCTAssertNil(GYNextFallbackPinyinCode(@"ge"));
}

- (void)testChainFromLongerWordStepsDownOneCharacterAtATime {
  // nihao -> niha -> nih -> (stop, "ni" would be next but nih is 3 chars
  // so one more step lands on "ni", which is exactly 2 and still valid)
  NSString *step1 = GYNextFallbackPinyinCode(@"nihao");
  XCTAssertEqualObjects(step1, @"niha");
  NSString *step2 = GYNextFallbackPinyinCode(step1);
  XCTAssertEqualObjects(step2, @"nih");
  NSString *step3 = GYNextFallbackPinyinCode(step2);
  XCTAssertEqualObjects(step3, @"ni");
  XCTAssertNil(GYNextFallbackPinyinCode(step3));
}

- (void)testStripsDanglingTrailingApostropheAfterDrop {
  // "ni'hao" (explicit syllable separator) drops its last letter to
  // "ni'ha", fine; but "ni'h" (hypothetically reached mid-ladder) dropping
  // its "h" would leave a bare trailing "'", which must also be stripped
  // rather than left as a malformed fallback code.
  XCTAssertEqualObjects(GYNextFallbackPinyinCode(@"ni'hao"), @"ni'ha");
  XCTAssertEqualObjects(GYNextFallbackPinyinCode(@"ni'h"), @"ni");
}

- (void)testStripsMultipleDanglingApostrophes {
  // Drop "d" -> "abc''" -> strip both trailing apostrophes -> "abc".
  XCTAssertEqualObjects(GYNextFallbackPinyinCode(@"abc''d"), @"abc");
}

- (void)testCascadingApostropheStripCanStillBottomOutBelowTwoCharacters {
  // Drop "b" -> "a''" -> strip both trailing apostrophes -> "a" (1 char) ->
  // below the minimum, so the whole call must return nil, not "a".
  XCTAssertNil(GYNextFallbackPinyinCode(@"a''b"));
}

- (void)testEmptyAndShortInputsReturnNil {
  XCTAssertNil(GYNextFallbackPinyinCode(@""));
  XCTAssertNil(GYNextFallbackPinyinCode(@"g"));
  XCTAssertNil(GYNextFallbackPinyinCode(@""));
}

- (void)testResultNeverGoesBelowTwoCharacters {
  NSString *code = @"zhuangxiubang";  // long, arbitrary
  NSUInteger steps = 0;
  while (code != nil) {
    XCTAssertGreaterThanOrEqual(code.length, (NSUInteger)2);
    code = GYNextFallbackPinyinCode(code);
    XCTAssertLessThan(++steps, (NSUInteger)50, @"ladder must terminate");
  }
}

@end
