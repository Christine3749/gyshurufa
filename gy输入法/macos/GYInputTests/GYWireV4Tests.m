#import <XCTest/XCTest.h>
#import "GYWireV4.h"

// Regression coverage for the Keep v4 wire parser (MACOS-KEEP-IMPLEMENTATION-
// SPEC.md §7, §11 自动化 checklist: "wire-v4 T/I/D、UTF-8、Base64、BigInt
// cursor"). Field counts and validation are cross-checked against the
// Windows client (native/src/GyKeepSync.cpp ParseWireEntries), which is what
// actually interoperates with production Keep today.
@interface GYWireV4Tests : XCTestCase
@end

@implementation GYWireV4Tests

static NSString *GYBase64(NSString *text) {
  return [[text dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
}

static NSString *GYWirePayload(NSString *wireBody) {
  return [[wireBody dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
}

#pragma mark - Empty / absent payload

- (void)testNilPayloadIsEmptyArray {
  XCTAssertEqualObjects(GYParseWireV4Payload(nil), @[]);
}

- (void)testEmptyStringPayloadIsEmptyArray {
  XCTAssertEqualObjects(GYParseWireV4Payload(@""), @[]);
}

- (void)testNotBase64IsRejected {
  XCTAssertNil(GYParseWireV4Payload(@"not-base64!!"));
}

#pragma mark - T (text) lines

- (void)testValidTextLineParsesAsAdd {
  NSString *wire = [NSString stringWithFormat:@"T\t42\tabcdef01\t1700000000000\t%@", GYBase64(@"你好，GY")];
  NSArray<GYWireChange *> *changes = GYParseWireV4Payload(GYWirePayload(wire));
  XCTAssertEqual(changes.count, 1u);
  GYWireChange *change = changes.firstObject;
  XCTAssertEqual(change.kind, GYWireChangeAdd);
  XCTAssertEqual(change.block.kind, GYBlockKindText);
  XCTAssertEqualObjects(change.block.entryId, @"abcdef01");
  XCTAssertEqualObjects(change.block.sequence, @"42");
  XCTAssertEqualObjects(change.block.text, @"你好，GY");
  XCTAssertEqualWithAccuracy(change.block.capturedAt, 1700000000.0, 0.001);
}

- (void)testTextLineWrongFieldCountRejectsWholePayload {
  // Only 4 fields (missing textBase64).
  NSString *wire = @"T\t42\tabcdef01\t1700000000000";
  XCTAssertNil(GYParseWireV4Payload(GYWirePayload(wire)));
}

- (void)testTextLineWithTrailingOriginDeviceIdIsRejected {
  // The spec table shows a trailing originDeviceId column, but the deployed
  // server/Windows client do not use one — 6 fields must be rejected, not
  // silently tolerated, or a subtly-different server response would parse
  // into the wrong columns.
  NSString *wire = [NSString stringWithFormat:@"T\t42\tabcdef01\t1700000000000\t%@\tdeviceA", GYBase64(@"hi")];
  XCTAssertNil(GYParseWireV4Payload(GYWirePayload(wire)));
}

- (void)testZeroSequenceRejected {
  NSString *wire = [NSString stringWithFormat:@"T\t0\tabcdef01\t1700000000000\t%@", GYBase64(@"hi")];
  XCTAssertNil(GYParseWireV4Payload(GYWirePayload(wire)));
}

- (void)testNonDecimalSequenceRejected {
  NSString *wire = [NSString stringWithFormat:@"T\t4x\tabcdef01\t1700000000000\t%@", GYBase64(@"hi")];
  XCTAssertNil(GYParseWireV4Payload(GYWirePayload(wire)));
}

- (void)testCapturedAtBeforeYear2000Rejected {
  NSString *wire = [NSString stringWithFormat:@"T\t42\tabcdef01\t123456\t%@", GYBase64(@"hi")];
  XCTAssertNil(GYParseWireV4Payload(GYWirePayload(wire)));
}

- (void)testInvalidEntryIdCharactersRejected {
  NSString *wire = [NSString stringWithFormat:@"T\t42\tabc def!\t1700000000000\t%@", GYBase64(@"hi")];
  XCTAssertNil(GYParseWireV4Payload(GYWirePayload(wire)));
}

- (void)testShortEntryIdRejected {
  NSString *wire = [NSString stringWithFormat:@"T\t42\tabc\t1700000000000\t%@", GYBase64(@"hi")];
  XCTAssertNil(GYParseWireV4Payload(GYWirePayload(wire)));
}

- (void)testEmptyDecodedTextRejected {
  NSString *wire = @"T\t42\tabcdef01\t1700000000000\t";
  XCTAssertNil(GYParseWireV4Payload(GYWirePayload(wire)));
}

- (void)testTextPreservesEmojiAndNewlines {
  NSString *original = @"line1\nline2\t🎉emoji";
  NSString *wire = [NSString stringWithFormat:@"T\t7\tabcdef01\t1700000000000\t%@", GYBase64(original)];
  NSArray<GYWireChange *> *changes = GYParseWireV4Payload(GYWirePayload(wire));
  // The text itself is base64'd, so an embedded real tab/newline in the
  // *decoded* text must not confuse line/field splitting.
  XCTAssertEqual(changes.count, 1u);
  XCTAssertEqualObjects(changes.firstObject.block.text, original);
}

#pragma mark - I (image) lines

- (NSString *)validSha256 {
  return [@"" stringByPaddingToLength:64 withString:@"ab12cd34" startingAtIndex:0];
}

- (void)testValidImageLineParsesAsAdd {
  NSString *wire = [NSString stringWithFormat:@"I\t99\timg12345\t1700000000000\timage/png\t1024\t%@", self.validSha256];
  NSArray<GYWireChange *> *changes = GYParseWireV4Payload(GYWirePayload(wire));
  XCTAssertEqual(changes.count, 1u);
  GYBlock *block = changes.firstObject.block;
  XCTAssertEqual(block.kind, GYBlockKindImage);
  XCTAssertEqual(block.byteSize, (NSUInteger)1024);
  XCTAssertEqualObjects(block.sha256, self.validSha256);
}

- (void)testImageWrongMimeRejected {
  NSString *wire = [NSString stringWithFormat:@"I\t99\timg12345\t1700000000000\timage/jpeg\t1024\t%@", self.validSha256];
  XCTAssertNil(GYParseWireV4Payload(GYWirePayload(wire)));
}

- (void)testImageZeroSizeRejected {
  NSString *wire = [NSString stringWithFormat:@"I\t99\timg12345\t1700000000000\timage/png\t0\t%@", self.validSha256];
  XCTAssertNil(GYParseWireV4Payload(GYWirePayload(wire)));
}

- (void)testImageOverTenMiBRejected {
  NSString *wire = [NSString stringWithFormat:@"I\t99\timg12345\t1700000000000\timage/png\t%llu\t%@",
                    (unsigned long long)(10 * 1024 * 1024 + 1), self.validSha256];
  XCTAssertNil(GYParseWireV4Payload(GYWirePayload(wire)));
}

- (void)testImageShortHashRejected {
  NSString *wire = @"I\t99\timg12345\t1700000000000\timage/png\t1024\tabc123";
  XCTAssertNil(GYParseWireV4Payload(GYWirePayload(wire)));
}

- (void)testImageUppercaseHashRejected {
  NSString *upper = [self.validSha256 uppercaseString];
  NSString *wire = [NSString stringWithFormat:@"I\t99\timg12345\t1700000000000\timage/png\t1024\t%@", upper];
  XCTAssertNil(GYParseWireV4Payload(GYWirePayload(wire)));
}

#pragma mark - D (delete) lines

- (void)testValidDeleteLine {
  NSString *wire = @"D\t100\tabcdef01";
  NSArray<GYWireChange *> *changes = GYParseWireV4Payload(GYWirePayload(wire));
  XCTAssertEqual(changes.count, 1u);
  XCTAssertEqual(changes.firstObject.kind, GYWireChangeDelete);
  XCTAssertEqualObjects(changes.firstObject.entryId, @"abcdef01");
}

- (void)testDeleteWithTrailingOriginDeviceIdRejected {
  NSString *wire = @"D\t100\tabcdef01\tdeviceA";
  XCTAssertNil(GYParseWireV4Payload(GYWirePayload(wire)));
}

#pragma mark - Mixed multi-line payloads (order preserved)

- (void)testMixedLinesPreserveOrderAndSkipBlankLines {
  NSString *wire = [NSString stringWithFormat:@"T\t1\tabcdef01\t1700000000000\t%@\n\nD\t2\tabcdef01\nT\t3\tzzzzzzzz\t1700000000000\t%@",
                    GYBase64(@"first"), GYBase64(@"second")];
  NSArray<GYWireChange *> *changes = GYParseWireV4Payload(GYWirePayload(wire));
  XCTAssertEqual(changes.count, 3u);
  XCTAssertEqual(changes[0].kind, GYWireChangeAdd);
  XCTAssertEqual(changes[1].kind, GYWireChangeDelete);
  XCTAssertEqual(changes[2].kind, GYWireChangeAdd);
}

- (void)testUnknownLineTypeRejectsWholePayload {
  NSString *wire = @"X\t1\tabcdef01";
  XCTAssertNil(GYParseWireV4Payload(GYWirePayload(wire)));
}

#pragma mark - GYParseSyncPage envelope

- (void)testParseSyncPageValidEnvelope {
  NSString *wire = [NSString stringWithFormat:@"T\t5\tabcdef01\t1700000000000\t%@", GYBase64(@"hi")];
  NSDictionary *json = @{@"ok": @YES, @"data": @{@"cursor": @"5", @"hasMore": @NO, @"payload": GYWirePayload(wire)}};
  NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
  NSString *cursor = nil;
  NSNumber *hasMore = nil;
  NSArray<GYWireChange *> *changes = GYParseSyncPage(data, &cursor, &hasMore);
  XCTAssertEqual(changes.count, 1u);
  XCTAssertEqualObjects(cursor, @"5");
  XCTAssertFalse(hasMore.boolValue);
}

- (void)testParseSyncPageAcceptsZeroCursor {
  NSDictionary *json = @{@"ok": @YES, @"data": @{@"cursor": @"0", @"hasMore": @NO, @"payload": @""}};
  NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
  NSString *cursor = nil;
  NSNumber *hasMore = nil;
  NSArray<GYWireChange *> *changes = GYParseSyncPage(data, &cursor, &hasMore);
  XCTAssertNotNil(changes);
  XCTAssertEqualObjects(cursor, @"0");
}

- (void)testParseSyncPageMissingCursorRejected {
  NSDictionary *json = @{@"ok": @YES, @"data": @{@"hasMore": @NO, @"payload": @""}};
  NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
  XCTAssertNil(GYParseSyncPage(data, NULL, NULL));
}

- (void)testParseSyncPageMalformedInnerPayloadRejectsWholePage {
  NSDictionary *json = @{@"ok": @YES, @"data": @{@"cursor": @"5", @"hasMore": @NO, @"payload": @"not-base64!!"}};
  NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
  XCTAssertNil(GYParseSyncPage(data, NULL, NULL));
}

#pragma mark - GYParseAckSequence

- (void)testParseAckSequenceValid {
  NSDictionary *json = @{@"ok": @YES, @"data": @{@"ack": @{@"id": @"abcdef01", @"sequence": @"42"}, @"cursor": @"42"}};
  NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
  XCTAssertEqualObjects(GYParseAckSequence(data), @"42");
}

- (void)testParseAckSequenceZeroRejected {
  NSDictionary *json = @{@"ok": @YES, @"data": @{@"ack": @{@"id": @"abcdef01", @"sequence": @"0"}}};
  NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
  XCTAssertNil(GYParseAckSequence(data));
}

- (void)testParseAckSequenceMissingAckRejected {
  NSDictionary *json = @{@"ok": @YES, @"data": @{@"cursor": @"42"}};
  NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
  XCTAssertNil(GYParseAckSequence(data));
}

#pragma mark - BigInt-scale sequences (spec: never lose precision via double)

- (void)testLargeSequenceSurvivesAsDecimalString {
  // 2^63-ish — would lose precision if ever routed through a double.
  NSString *big = @"9223372036854775800";
  NSString *wire = [NSString stringWithFormat:@"T\t%@\tabcdef01\t1700000000000\t%@", big, GYBase64(@"hi")];
  NSArray<GYWireChange *> *changes = GYParseWireV4Payload(GYWirePayload(wire));
  XCTAssertEqualObjects(changes.firstObject.block.sequence, big);
}

@end
