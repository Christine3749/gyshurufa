#import <XCTest/XCTest.h>
#import "GYSyncFormatNegotiation.h"

// Coverage for the four negotiation requirements raised in review:
//   1. A v4-requested round that actually comes back v3-shaped must
//      downgrade, not silently misparse or stay stuck.
//   2. v4 is only ever confirmed after an authenticated 200 whose body
//      actually parses as the v4 shape — never on request intent alone.
//   3. 401/404/503 (and other non-200s) must never change the protocol mode
//      in either direction.
//   4. After any failure to confirm v4, v3 sync capability is always what
//      remains — there is no third, broken mode.
@interface GYSyncFormatNegotiationTests : XCTestCase
@end

@implementation GYSyncFormatNegotiationTests

#pragma mark - 1. v4 requested, server actually returns v3 shape -> downgrade

- (void)testV4RequestButV3ShapedResponseDowngradesFromV4Confirmed {
  GYSyncFormatMode next = GYNextSyncFormatMode(GYSyncFormatV4Confirmed, /*requestedV4=*/YES,
                                                /*status=*/200, /*v4Shape=*/NO, /*v3Shape=*/YES);
  XCTAssertEqual(next, GYSyncFormatV3Only);
}

- (void)testV4RequestButV3ShapedResponseStaysV3OnlyFromV3Only {
  // Same fallback, starting from the mode that's already the current
  // default — must not error or leave the mode undefined.
  GYSyncFormatMode next = GYNextSyncFormatMode(GYSyncFormatV3Only, YES, 200, NO, YES);
  XCTAssertEqual(next, GYSyncFormatV3Only);
}

#pragma mark - 2. v4 confirmed only on authenticated 200 with an actual v4-shaped body

- (void)testAuthenticated200WithV4ShapeConfirmsV4 {
  GYSyncFormatMode next = GYNextSyncFormatMode(GYSyncFormatV3Only, YES, 200, /*v4Shape=*/YES, NO);
  XCTAssertEqual(next, GYSyncFormatV4Confirmed);
}

- (void)testRequestingV4AloneNeverConfirmsWithoutA200Response {
  // Intent to request v4 is not evidence of anything — only the response
  // matters. Every non-200 status must fail to confirm.
  for (NSNumber *status in @[@0, @400, @401, @403, @404, @429, @500, @503]) {
    GYSyncFormatMode next = GYNextSyncFormatMode(GYSyncFormatV3Only, YES, status.integerValue, YES, NO);
    XCTAssertEqual(next, GYSyncFormatV3Only, @"status %@ must not confirm v4 even with a v4-shaped body", status);
  }
}

// Review finding: an empty payload (an entirely ordinary "nothing new to
// sync" response — GYParseSyncWireV3Payload(nil/"") and
// GYParseSyncWireV4Payload(nil/"") BOTH return an empty array) made both
// shape flags YES simultaneously. The original implementation checked
// v4Shape before v3Shape with no exclusivity check, so this reachable,
// common case silently promoted to V4Confirmed on zero actual v4 evidence.
- (void)testBothShapesMatchingAmbiguousResponseDoesNotPromoteToV4 {
  GYSyncFormatMode next = GYNextSyncFormatMode(GYSyncFormatV3Only, YES, 200, /*v4Shape=*/YES, /*v3Shape=*/YES);
  XCTAssertEqual(next, GYSyncFormatV3Only, @"an ambiguous (empty-payload) response must not confirm v4");
}

- (void)testBothShapesMatchingAmbiguousResponseDoesNotDemoteFromV4 {
  GYSyncFormatMode next = GYNextSyncFormatMode(GYSyncFormatV4Confirmed, YES, 200, YES, YES);
  XCTAssertEqual(next, GYSyncFormatV4Confirmed, @"an ambiguous (empty-payload) response must not undo an "
                 @"already-confirmed v4 mode either");
}

- (void)testCorruptTwoHundredResponseDoesNotConfirmV4 {
  // 200 but the body parses as neither shape (truncated, wrong envelope,
  // etc.) — must not guess; stay in the current mode and let the next round
  // retry cleanly.
  GYSyncFormatMode next = GYNextSyncFormatMode(GYSyncFormatV3Only, YES, 200, NO, NO);
  XCTAssertEqual(next, GYSyncFormatV3Only);
  GYSyncFormatMode nextFromConfirmed = GYNextSyncFormatMode(GYSyncFormatV4Confirmed, YES, 200, NO, NO);
  XCTAssertEqual(nextFromConfirmed, GYSyncFormatV4Confirmed, @"a single corrupt page must not silently drop an "
                 @"already-confirmed v4 mode");
}

#pragma mark - 3. 401/404/503/etc never change the protocol mode in either direction

- (void)testNonTwoHundredStatusesNeverChangeModeFromV3Only {
  for (NSNumber *status in @[@401, @404, @429, @500, @503]) {
    // Try every combination of what the (irrelevant, since status != 200)
    // body would have parsed as — none of it should matter.
    for (NSNumber *v4Shape in @[@YES, @NO]) {
      for (NSNumber *v3Shape in @[@YES, @NO]) {
        GYSyncFormatMode next = GYNextSyncFormatMode(GYSyncFormatV3Only, YES, status.integerValue,
                                                       v4Shape.boolValue, v3Shape.boolValue);
        XCTAssertEqual(next, GYSyncFormatV3Only, @"status %@ must leave V3Only unchanged", status);
      }
    }
  }
}

- (void)testNonTwoHundredStatusesNeverChangeModeFromV4Confirmed {
  for (NSNumber *status in @[@401, @404, @429, @500, @503]) {
    GYSyncFormatMode next = GYNextSyncFormatMode(GYSyncFormatV4Confirmed, YES, status.integerValue, NO, NO);
    XCTAssertEqual(next, GYSyncFormatV4Confirmed,
                   @"a transient status %@ must not look like v4 got disabled", status);
  }
}

#pragma mark - 4. v4 confirmation failing always leaves v3 sync capability intact

- (void)testEveryFailureToConfirmV4ResolvesToAValidMode {
  // Exhaustive over the boolean/enum input space: the result is always one
  // of the two defined modes, never an undefined third state — so "v3 is
  // always available" is true by construction, not by convention.
  NSArray<NSNumber *> *modes = @[@(GYSyncFormatV3Only), @(GYSyncFormatV4Confirmed)];
  NSArray<NSNumber *> *statuses = @[@0, @200, @401, @404, @429, @500, @503];
  for (NSNumber *mode in modes) {
    for (NSNumber *requestedV4 in @[@YES, @NO]) {
      for (NSNumber *status in statuses) {
        for (NSNumber *v4Shape in @[@YES, @NO]) {
          for (NSNumber *v3Shape in @[@YES, @NO]) {
            GYSyncFormatMode next = GYNextSyncFormatMode((GYSyncFormatMode)mode.integerValue, requestedV4.boolValue,
                                                          status.integerValue, v4Shape.boolValue, v3Shape.boolValue);
            XCTAssertTrue(next == GYSyncFormatV3Only || next == GYSyncFormatV4Confirmed);
          }
        }
      }
    }
  }
}

- (void)testOrdinaryV3RoundsNeverTouchTheMode {
  // The overwhelming majority of rounds never request v4 at all (GYKeepSync
  // does not yet). Those rounds must be complete no-ops for the negotiation
  // state, regardless of status or shape.
  GYSyncFormatMode next = GYNextSyncFormatMode(GYSyncFormatV4Confirmed, /*requestedV4=*/NO, 200, NO, YES);
  XCTAssertEqual(next, GYSyncFormatV4Confirmed);
  GYSyncFormatMode next2 = GYNextSyncFormatMode(GYSyncFormatV3Only, /*requestedV4=*/NO, 401, YES, NO);
  XCTAssertEqual(next2, GYSyncFormatV3Only);
}

- (void)testV4ConfirmedCanLaterBeDetectedAndRevertedIfServerRollsBack {
  // If the server later stops honoring format=wire-v4 (rollback, config
  // change, etc.), the very next v4-requested round that comes back
  // v3-shaped must revert — v4Confirmed is not a one-way, permanent switch.
  GYSyncFormatMode next = GYNextSyncFormatMode(GYSyncFormatV4Confirmed, YES, 200, NO, YES);
  XCTAssertEqual(next, GYSyncFormatV3Only);
}

@end
