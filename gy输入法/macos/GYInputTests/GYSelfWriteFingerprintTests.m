#import <XCTest/XCTest.h>
#import "GYSelfWriteFingerprint.h"

// Coverage for the 用户复制竞争 (user-copy race) case: GYClipboardHistory
// writes remote content to the pasteboard, then must tell that write apart
// from a genuine user ⌘C landing on the very next poll tick. See
// MACOS-KEEP-IMPLEMENTATION-SPEC.md 附录 A, incident C-03, and the rationale
// in GYSelfWriteFingerprint.h.
@interface GYSelfWriteFingerprintTests : XCTestCase
@end

@implementation GYSelfWriteFingerprintTests

- (void)testMatchingFingerprintAndChangeCountIsOwnWrite {
  XCTAssertTrue(GYIsOwnPasteboardWrite(@"hello from Keep", 42, @"hello from Keep", 42));
}

- (void)testNoSelfWriteRecordedIsNeverSuppressed {
  // Nothing was ever written by us — any observation is a real user copy.
  XCTAssertFalse(GYIsOwnPasteboardWrite(nil, 0, @"hello from Keep", 42));
}

// The actual race: the poll after our write lands on the SAME changeCount
// (the write and the read happened to interleave with nothing in between),
// but the user grabbed the race window and copied something *different* at
// that exact moment. This must NOT be suppressed — the whole point of
// fingerprinting by content instead of just changeCount.
- (void)testSameChangeCountDifferentContentIsRealUserCopyNotSuppressed {
  XCTAssertFalse(GYIsOwnPasteboardWrite(@"remote text", 42, @"user's own new copy", 42));
}

// The mirror case: same content, but observed at a different changeCount —
// e.g. the user copied the exact same string we just wrote, coincidentally.
// changeCount not matching means it is a distinct pasteboard transaction, so
// it must be treated as a new copy, not swallowed as an echo of our write.
- (void)testSameContentDifferentChangeCountIsNotSuppressed {
  XCTAssertFalse(GYIsOwnPasteboardWrite(@"remote text", 42, @"remote text", 43));
}

- (void)testEarlierChangeCountIsNotSuppressed {
  // Should not happen in practice (changeCount only increases), but the
  // decision function must fail closed rather than assume monotonicity.
  XCTAssertFalse(GYIsOwnPasteboardWrite(@"remote text", 42, @"remote text", 41));
}

- (void)testNilObservedFingerprintIsNotSuppressed {
  // e.g. the poll read back a non-string pasteboard type at the same
  // changeCount — must not crash and must not suppress.
  XCTAssertFalse(GYIsOwnPasteboardWrite(@"remote text", 42, nil, 42));
}

- (void)testImageFingerprintsUseSameDecisionAsText {
  // GYClipboardHistory reuses this same function for images, with a SHA-256
  // hex string as the fingerprint instead of raw text — the decision logic
  // itself does not care which kind of string it is.
  NSString *sha = @"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
  XCTAssertTrue(GYIsOwnPasteboardWrite(sha, 10, sha, 10));
  NSString *differentSha = @"2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824";
  XCTAssertFalse(GYIsOwnPasteboardWrite(sha, 10, differentSha, 10));
}

@end
