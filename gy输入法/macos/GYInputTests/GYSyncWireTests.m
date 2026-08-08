#import <XCTest/XCTest.h>
#import "GYSyncWire.h"

// Regression coverage for GYSyncWire's two line formats. See the NAMING note
// in GYSyncWire.h for the full story; short version:
//   v3 (no `format=` param) — cross-checked field-for-field against the
//     Windows client (native/src/GyKeepSync.cpp ParseWireEntries), which is
//     what actually interoperates with production Keep today.
//   v4 (`?format=wire-v4`, adds a trailing originDeviceId) — confirmed as
//     real, separate server code by reading
//     apps/keep/lib/clipboard-wire.ts at commit 2bf366b (wireSnapshotV4/
//     wireChangesV4), not inferred from a bare 401 probe. Whether it is
//     live on the currently deployed revision, and whether either shipped
//     client requests it, are separate open questions — GYKeepSync does not
//     request it.
@interface GYSyncWireTests : XCTestCase
@end

@implementation GYSyncWireTests

static NSString *GYBase64(NSString *text) {
  return [[text dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
}

static NSString *GYWirePayload(NSString *wireBody) {
  return [[wireBody dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
}

#pragma mark - Empty / absent payload

- (void)testNilPayloadIsEmptyArray {
  XCTAssertEqualObjects(GYParseSyncWireV3Payload(nil), @[]);
}

- (void)testEmptyStringPayloadIsEmptyArray {
  XCTAssertEqualObjects(GYParseSyncWireV3Payload(@""), @[]);
}

- (void)testNotBase64IsRejected {
  XCTAssertNil(GYParseSyncWireV3Payload(@"not-base64!!"));
}

#pragma mark - T (text) lines

- (void)testValidTextLineParsesAsAdd {
  NSString *wire = [NSString stringWithFormat:@"T\t42\tabcdef01\t1700000000000\t%@", GYBase64(@"你好，GY")];
  NSArray<GYWireChange *> *changes = GYParseSyncWireV3Payload(GYWirePayload(wire));
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
  XCTAssertNil(GYParseSyncWireV3Payload(GYWirePayload(wire)));
}

- (void)testTextLineWithTrailingOriginDeviceIdIsRejectedByV3Parser {
  // This is the real v4 shape (see GYSyncWire.h NAMING note) — the v3 parser
  // must reject it outright, not silently tolerate or misparse it, since
  // GYKeepSync only ever requests v3.
  NSString *wire = [NSString stringWithFormat:@"T\t42\tabcdef01\t1700000000000\t%@\tdeviceA", GYBase64(@"hi")];
  XCTAssertNil(GYParseSyncWireV3Payload(GYWirePayload(wire)));
}

- (void)testZeroSequenceRejected {
  NSString *wire = [NSString stringWithFormat:@"T\t0\tabcdef01\t1700000000000\t%@", GYBase64(@"hi")];
  XCTAssertNil(GYParseSyncWireV3Payload(GYWirePayload(wire)));
}

- (void)testNonDecimalSequenceRejected {
  NSString *wire = [NSString stringWithFormat:@"T\t4x\tabcdef01\t1700000000000\t%@", GYBase64(@"hi")];
  XCTAssertNil(GYParseSyncWireV3Payload(GYWirePayload(wire)));
}

- (void)testCapturedAtBeforeYear2000Rejected {
  NSString *wire = [NSString stringWithFormat:@"T\t42\tabcdef01\t123456\t%@", GYBase64(@"hi")];
  XCTAssertNil(GYParseSyncWireV3Payload(GYWirePayload(wire)));
}

- (void)testInvalidEntryIdCharactersRejected {
  NSString *wire = [NSString stringWithFormat:@"T\t42\tabc def!\t1700000000000\t%@", GYBase64(@"hi")];
  XCTAssertNil(GYParseSyncWireV3Payload(GYWirePayload(wire)));
}

- (void)testShortEntryIdRejected {
  NSString *wire = [NSString stringWithFormat:@"T\t42\tabc\t1700000000000\t%@", GYBase64(@"hi")];
  XCTAssertNil(GYParseSyncWireV3Payload(GYWirePayload(wire)));
}

- (void)testEmptyDecodedTextRejected {
  NSString *wire = @"T\t42\tabcdef01\t1700000000000\t";
  XCTAssertNil(GYParseSyncWireV3Payload(GYWirePayload(wire)));
}

- (void)testTextPreservesEmojiAndNewlines {
  NSString *original = @"line1\nline2\t🎉emoji";
  NSString *wire = [NSString stringWithFormat:@"T\t7\tabcdef01\t1700000000000\t%@", GYBase64(original)];
  NSArray<GYWireChange *> *changes = GYParseSyncWireV3Payload(GYWirePayload(wire));
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
  NSArray<GYWireChange *> *changes = GYParseSyncWireV3Payload(GYWirePayload(wire));
  XCTAssertEqual(changes.count, 1u);
  GYBlock *block = changes.firstObject.block;
  XCTAssertEqual(block.kind, GYBlockKindImage);
  XCTAssertEqual(block.byteSize, (NSUInteger)1024);
  XCTAssertEqualObjects(block.sha256, self.validSha256);
}

- (void)testImageWrongMimeRejected {
  NSString *wire = [NSString stringWithFormat:@"I\t99\timg12345\t1700000000000\timage/jpeg\t1024\t%@", self.validSha256];
  XCTAssertNil(GYParseSyncWireV3Payload(GYWirePayload(wire)));
}

- (void)testImageZeroSizeRejected {
  NSString *wire = [NSString stringWithFormat:@"I\t99\timg12345\t1700000000000\timage/png\t0\t%@", self.validSha256];
  XCTAssertNil(GYParseSyncWireV3Payload(GYWirePayload(wire)));
}

- (void)testImageOverTenMiBRejected {
  NSString *wire = [NSString stringWithFormat:@"I\t99\timg12345\t1700000000000\timage/png\t%llu\t%@",
                    (unsigned long long)(10 * 1024 * 1024 + 1), self.validSha256];
  XCTAssertNil(GYParseSyncWireV3Payload(GYWirePayload(wire)));
}

- (void)testImageShortHashRejected {
  NSString *wire = @"I\t99\timg12345\t1700000000000\timage/png\t1024\tabc123";
  XCTAssertNil(GYParseSyncWireV3Payload(GYWirePayload(wire)));
}

- (void)testImageUppercaseHashRejected {
  NSString *upper = [self.validSha256 uppercaseString];
  NSString *wire = [NSString stringWithFormat:@"I\t99\timg12345\t1700000000000\timage/png\t1024\t%@", upper];
  XCTAssertNil(GYParseSyncWireV3Payload(GYWirePayload(wire)));
}

#pragma mark - D (delete) lines

- (void)testValidDeleteLine {
  NSString *wire = @"D\t100\tabcdef01";
  NSArray<GYWireChange *> *changes = GYParseSyncWireV3Payload(GYWirePayload(wire));
  XCTAssertEqual(changes.count, 1u);
  XCTAssertEqual(changes.firstObject.kind, GYWireChangeDelete);
  XCTAssertEqualObjects(changes.firstObject.entryId, @"abcdef01");
}

- (void)testDeleteWithTrailingOriginDeviceIdRejectedByV3Parser {
  NSString *wire = @"D\t100\tabcdef01\tdeviceA";
  XCTAssertNil(GYParseSyncWireV3Payload(GYWirePayload(wire)));
}

#pragma mark - Mixed multi-line payloads (order preserved)

- (void)testMixedLinesPreserveOrderAndSkipBlankLines {
  NSString *wire = [NSString stringWithFormat:@"T\t1\tabcdef01\t1700000000000\t%@\n\nD\t2\tabcdef01\nT\t3\tzzzzzzzz\t1700000000000\t%@",
                    GYBase64(@"first"), GYBase64(@"second")];
  NSArray<GYWireChange *> *changes = GYParseSyncWireV3Payload(GYWirePayload(wire));
  XCTAssertEqual(changes.count, 3u);
  XCTAssertEqual(changes[0].kind, GYWireChangeAdd);
  XCTAssertEqual(changes[1].kind, GYWireChangeDelete);
  XCTAssertEqual(changes[2].kind, GYWireChangeAdd);
}

- (void)testUnknownLineTypeRejectsWholePayload {
  NSString *wire = @"X\t1\tabcdef01";
  XCTAssertNil(GYParseSyncWireV3Payload(GYWirePayload(wire)));
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
  NSArray<GYWireChange *> *changes = GYParseSyncWireV3Payload(GYWirePayload(wire));
  XCTAssertEqualObjects(changes.firstObject.block.sequence, big);
}

#pragma mark - v4 (format=wire-v4): confirmed-real shape, not yet requested by the client

- (void)testV4TextLineParsesOriginDeviceId {
  NSString *wire = [NSString stringWithFormat:@"T\t42\tabcdef01\t1700000000000\t%@\tdeviceAAAA", GYBase64(@"hi")];
  NSArray<GYWireChange *> *changes = GYParseSyncWireV4Payload(GYWirePayload(wire));
  XCTAssertEqual(changes.count, 1u);
  XCTAssertEqualObjects(changes.firstObject.originDeviceId, @"deviceAAAA");
  XCTAssertEqualObjects(changes.firstObject.block.originDeviceId, @"deviceAAAA");
}

- (void)testV4TextLineAllowsEmptyOriginDeviceId {
  NSString *wire = [NSString stringWithFormat:@"T\t42\tabcdef01\t1700000000000\t%@\t", GYBase64(@"hi")];
  NSArray<GYWireChange *> *changes = GYParseSyncWireV4Payload(GYWirePayload(wire));
  XCTAssertEqual(changes.count, 1u);
  XCTAssertEqualObjects(changes.firstObject.originDeviceId, @"");
  XCTAssertNil(changes.firstObject.block.originDeviceId);
}

- (void)testV4ImageLineParsesOriginDeviceId {
  NSString *sha = [@"" stringByPaddingToLength:64 withString:@"ab12cd34" startingAtIndex:0];
  NSString *wire = [NSString stringWithFormat:@"I\t99\timg12345\t1700000000000\timage/png\t1024\t%@\tdeviceBBBB", sha];
  NSArray<GYWireChange *> *changes = GYParseSyncWireV4Payload(GYWirePayload(wire));
  XCTAssertEqual(changes.count, 1u);
  XCTAssertEqualObjects(changes.firstObject.originDeviceId, @"deviceBBBB");
}

- (void)testV4DeleteLineParsesOriginDeviceId {
  NSString *wire = @"D\t100\tabcdef01\tdeviceCCCC";
  NSArray<GYWireChange *> *changes = GYParseSyncWireV4Payload(GYWirePayload(wire));
  XCTAssertEqual(changes.count, 1u);
  XCTAssertEqualObjects(changes.firstObject.originDeviceId, @"deviceCCCC");
}

- (void)testV4RejectsV3ShapeMissingOriginField {
  // The inverse of the v3 tests above: feeding v3's shorter shape to the v4
  // parser must also fail closed, not silently default the missing field.
  NSString *wire = [NSString stringWithFormat:@"T\t42\tabcdef01\t1700000000000\t%@", GYBase64(@"hi")];
  XCTAssertNil(GYParseSyncWireV4Payload(GYWirePayload(wire)));
}

- (void)testV4RejectsMalformedOriginDeviceId {
  NSString *wire = [NSString stringWithFormat:@"T\t42\tabcdef01\t1700000000000\t%@\tnot valid!", GYBase64(@"hi")];
  XCTAssertNil(GYParseSyncWireV4Payload(GYWirePayload(wire)));
}

#pragma mark - GYSHA256Hex (shared by GYKeepSync image download-verify and GYClipboardHistory capture)

- (void)testSHA256HexKnownVectors {
  // Standard test vectors, cross-checked against `python3 -c "import
  // hashlib; print(hashlib.sha256(b'...').hexdigest())"` independently of
  // this codebase, not hand-derived from GYSHA256Hex itself.
  XCTAssertEqualObjects(GYSHA256Hex([NSData data]),
                         @"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  XCTAssertEqualObjects(GYSHA256Hex([@"hello" dataUsingEncoding:NSUTF8StringEncoding]),
                         @"2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824");
}

- (void)testSHA256HexIsDeterministicAndContentSensitive {
  NSData *a = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
  NSData *b = [@"hello!" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertEqualObjects(GYSHA256Hex(a), GYSHA256Hex(a));
  XCTAssertNotEqualObjects(GYSHA256Hex(a), GYSHA256Hex(b));
}

@end
