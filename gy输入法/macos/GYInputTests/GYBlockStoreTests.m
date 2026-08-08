#import <XCTest/XCTest.h>
#import "GYBlockStore.h"
#import "GYSyncWire.h"

// Coverage for GYBlockStore against the five scenarios spec §11's
// acceptance checklist calls out for the reliable Outbox: offline capture
// past the 20-entry HEAD view, restart recovery, DELETE, and image hash
// integrity. (The fifth scenario, 用户复制竞争 / user-copy race, is a
// pasteboard-capture concern, not a storage one — see
// GYSelfWriteFingerprintTests.m instead.)
//
// Each test opens its own throwaway sqlite file via `storeAtPath:` (see
// GYBlockStore.h) rather than touching the app's `sharedStore` singleton, so
// these tests are isolated from each other and from any real installation.
@interface GYBlockStoreTests : XCTestCase
@property(nonatomic, copy) NSString *tempDirectory;
@end

@implementation GYBlockStoreTests

- (void)setUp {
  self.tempDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID UUIDString]];
  [NSFileManager.defaultManager createDirectoryAtPath:self.tempDirectory withIntermediateDirectories:YES attributes:nil error:nil];
}

- (void)tearDown {
  [NSFileManager.defaultManager removeItemAtPath:self.tempDirectory error:nil];
}

- (NSString *)freshDBPath {
  return [self.tempDirectory stringByAppendingPathComponent:[[NSUUID.UUID UUIDString] stringByAppendingString:@".sqlite"]];
}

- (GYBlockStore *)freshStore {
  return [GYBlockStore storeAtPath:[self freshDBPath]];
}

- (NSString *)newEntryId {
  return [NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
}

- (GYBlock *)confirmedTextBlockWithId:(NSString *)entryId sequence:(NSString *)sequence text:(NSString *)text {
  GYBlock *block = [[GYBlock alloc] init];
  block.entryId = entryId;
  block.kind = GYBlockKindText;
  block.capturedAt = NSDate.date.timeIntervalSince1970;
  block.state = GYBlockStateConfirmed;
  block.sequence = sequence;
  block.text = text;
  return block;
}

#pragma mark - 离线 30 条 (offline capture past the HEAD-20 view)

- (void)testThirtyOfflineCapturesAllSurviveInOutbox {
  GYBlockStore *store = [self freshStore];
  NSMutableArray<NSString *> *ids = [NSMutableArray array];
  for (NSUInteger i = 0; i < 30; ++i) {
    NSString *entryId = [self newEntryId];
    [ids addObject:entryId];
    GYBlock *block = [store insertCapturedTextBlock:[NSString stringWithFormat:@"offline copy #%lu", (unsigned long)i]
                                          capturedAt:NSDate.date.timeIntervalSince1970 + i
                                             entryId:entryId];
    XCTAssertNotNil(block, @"capture #%lu should not be dropped", (unsigned long)i);
  }
  // The Outbox is not the 20-entry view: all 30 must still be pending.
  XCTAssertEqual(store.pendingOutbox.count, (NSUInteger)30);
  // The HEAD view IS capped at 20, but that's a view limit, not data loss —
  // the other 10 are still retrievable via pendingOutbox above.
  XCTAssertEqual([store headProjectionWithLimit:20].count, (NSUInteger)20);
  // Outbox drains oldest-first, matching capture order (so Keep's resulting
  // order matches the order the user actually copied things in).
  NSArray<GYBlock *> *outbox = store.pendingOutbox;
  for (NSUInteger i = 0; i < 30; ++i) {
    XCTAssertEqualObjects(outbox[i].entryId, ids[i], @"outbox position %lu", (unsigned long)i);
  }
}

- (void)testAcknowledgingSomeOfflineCapturesLeavesRestPending {
  GYBlockStore *store = [self freshStore];
  NSMutableArray<NSString *> *ids = [NSMutableArray array];
  for (NSUInteger i = 0; i < 30; ++i) {
    NSString *entryId = [self newEntryId];
    [ids addObject:entryId];
    [store insertCapturedTextBlock:[NSString stringWithFormat:@"offline copy #%lu", (unsigned long)i]
                         capturedAt:NSDate.date.timeIntervalSince1970 + i
                            entryId:entryId];
  }
  // Simulate reconnecting and draining the first 12, oldest-first.
  for (NSUInteger i = 0; i < 12; ++i) {
    NSString *sequence = [NSString stringWithFormat:@"%lu", (unsigned long)(i + 1)];
    XCTAssertTrue([store acknowledgeEntryId:ids[i] sequence:sequence]);
  }
  XCTAssertEqual(store.pendingOutbox.count, (NSUInteger)18);
  NSArray<NSString *> *acknowledgedIds = [ids subarrayWithRange:NSMakeRange(0, 12)];
  for (GYBlock *remaining in store.pendingOutbox) {
    XCTAssertFalse([acknowledgedIds containsObject:remaining.entryId],
                    @"an acknowledged entry must not still be in the outbox");
  }
}

#pragma mark - 重启恢复 (restart recovery)

// This is exactly the scenario the pre-rewrite pending-bit bug lived in:
// the old GYKeepSync mutated an in-memory GYClipboardEntry's pendingUpload
// flag directly, which made GYClipboardHistory's identical-array diff check
// a no-op, so the cleared flag never actually reached disk — a restart would
// have re-uploaded everything and verify-keep-sync.sh could never observe a
// real ACK. Here that is checked directly: reopen a fresh sqlite3 connection
// against the same file and assert the state actually persisted.
- (void)testRestartRecoveryPreservesQueuedAndConfirmedState {
  NSString *path = [self freshDBPath];
  GYBlockStore *before = [GYBlockStore storeAtPath:path];
  NSString *queuedId = [self newEntryId];
  NSString *confirmedId = [self newEntryId];
  [before insertCapturedTextBlock:@"still queued" capturedAt:NSDate.date.timeIntervalSince1970 entryId:queuedId];
  [before insertCapturedTextBlock:@"about to be acked" capturedAt:NSDate.date.timeIntervalSince1970 entryId:confirmedId];
  XCTAssertTrue([before acknowledgeEntryId:confirmedId sequence:@"77"]);

  // "Quit app, relaunch": a brand new GYBlockStore instance, brand new
  // sqlite3 connection, same file on disk.
  GYBlockStore *after = [GYBlockStore storeAtPath:path];

  GYBlock *queuedAfterRestart = [after blockForEntryId:queuedId];
  XCTAssertEqual(queuedAfterRestart.state, GYBlockStateQueued);
  XCTAssertNil(queuedAfterRestart.sequence);

  GYBlock *confirmedAfterRestart = [after blockForEntryId:confirmedId];
  XCTAssertEqual(confirmedAfterRestart.state, GYBlockStateConfirmed);
  XCTAssertEqualObjects(confirmedAfterRestart.sequence, @"77");

  // The confirmed one must not still be sitting in the outbox waiting for a
  // pointless re-upload after restart.
  NSArray<GYBlock *> *outboxAfterRestart = after.pendingOutbox;
  XCTAssertEqual(outboxAfterRestart.count, (NSUInteger)1);
  XCTAssertEqualObjects(outboxAfterRestart.firstObject.entryId, queuedId);
}

- (void)testRestartRecoveryPreservesCursor {
  NSString *path = [self freshDBPath];
  GYBlockStore *before = [GYBlockStore storeAtPath:path];
  [before setCursor:@"12345" forAccount:@"user@example.com"];

  GYBlockStore *after = [GYBlockStore storeAtPath:path];
  XCTAssertEqualObjects([after cursorForAccount:@"user@example.com"], @"12345");
  // A different account's cursor must not bleed into or out of this one.
  XCTAssertEqualObjects([after cursorForAccount:@"other@example.com"], @"0");
}

- (void)testRestartRecoveryPreservesDeviceId {
  NSString *path = [self freshDBPath];
  NSString *deviceIdBefore = [GYBlockStore storeAtPath:path].deviceId;
  NSString *deviceIdAfter = [GYBlockStore storeAtPath:path].deviceId;
  XCTAssertEqualObjects(deviceIdBefore, deviceIdAfter, @"device id must survive a restart — spec §7.1: "
                        @"\"不能随每次启动变化\"");
}

#pragma mark - DELETE (tombstone from a remote device)

- (void)testDeleteRemovesConfirmedBlockFromHeadView {
  GYBlockStore *store = [self freshStore];
  NSString *entryId = [self newEntryId];
  [store applyConfirmedAdd:[self confirmedTextBlockWithId:entryId sequence:@"5" text:@"hello"]];
  XCTAssertNotNil([store blockForEntryId:entryId]);

  [store applyDeleteEntryId:entryId];

  XCTAssertNil([store blockForEntryId:entryId]);
  XCTAssertEqual([store headProjectionWithLimit:20].count, (NSUInteger)0);
}

- (void)testDeleteDoesNotAffectUnrelatedQueuedEntries {
  GYBlockStore *store = [self freshStore];
  NSString *confirmedId = [self newEntryId];
  NSString *queuedId = [self newEntryId];
  [store applyConfirmedAdd:[self confirmedTextBlockWithId:confirmedId sequence:@"5" text:@"from Keep"]];
  [store insertCapturedTextBlock:@"still local" capturedAt:NSDate.date.timeIntervalSince1970 entryId:queuedId];

  [store applyDeleteEntryId:confirmedId];

  XCTAssertNil([store blockForEntryId:confirmedId]);
  XCTAssertNotNil([store blockForEntryId:queuedId]);
  XCTAssertEqual(store.pendingOutbox.count, (NSUInteger)1);
}

- (void)testDeleteOfUnknownEntryIdIsSafeNoOp {
  GYBlockStore *store = [self freshStore];
  XCTAssertNoThrow([store applyDeleteEntryId:@"never-existed-00000000"]);
}

- (void)testDeleteExposesTwentyFirstConfirmedEntry {
  // The 20-entry HEAD view formula: deleting one confirmed entry must let
  // the 21st-oldest confirmed entry (previously hidden by the cap) surface —
  // this is what motivates GYKeepSync's post-DELETE snapshot refresh.
  GYBlockStore *store = [self freshStore];
  NSMutableArray<NSString *> *ids = [NSMutableArray array];
  for (NSUInteger i = 0; i < 21; ++i) {
    NSString *entryId = [self newEntryId];
    [ids addObject:entryId];
    [store applyConfirmedAdd:[self confirmedTextBlockWithId:entryId
                                                     sequence:[NSString stringWithFormat:@"%lu", (unsigned long)(i + 1)]
                                                         text:[NSString stringWithFormat:@"entry %lu", (unsigned long)i]]];
  }
  NSArray<GYBlock *> *headBefore = [store headProjectionWithLimit:20];
  XCTAssertEqual(headBefore.count, (NSUInteger)20);
  XCTAssertFalse([[headBefore valueForKey:@"entryId"] containsObject:ids[0]], @"oldest entry starts outside the view");

  [store applyDeleteEntryId:ids[1]];  // delete one of the 20 visible ones

  NSArray<GYBlock *> *headAfter = [store headProjectionWithLimit:20];
  XCTAssertEqual(headAfter.count, (NSUInteger)20);
  XCTAssertTrue([[headAfter valueForKey:@"entryId"] containsObject:ids[0]],
                @"deleting a visible entry should let the 21st-oldest confirmed entry fill the gap");
}

#pragma mark - 图片 hash (image capture/round-trip integrity)

- (void)testImageBlockRoundTripsHashAndSize {
  GYBlockStore *store = [self freshStore];
  NSData *pngBytes = [@"pretend this is PNG bytes" dataUsingEncoding:NSUTF8StringEncoding];
  NSString *sha = GYSHA256Hex(pngBytes);
  NSString *entryId = [self newEntryId];

  GYBlock *inserted = [store insertCapturedImageBlockAt:NSDate.date.timeIntervalSince1970
                                                  entryId:entryId
                                                   sha256:sha
                                                 byteSize:pngBytes.length
                                                 blobPath:@"/tmp/does-not-matter.png"];
  XCTAssertNotNil(inserted);

  GYBlock *reloaded = [store blockForEntryId:entryId];
  XCTAssertEqual(reloaded.kind, GYBlockKindImage);
  XCTAssertEqualObjects(reloaded.sha256, sha);
  XCTAssertEqual(reloaded.byteSize, pngBytes.length);
}

- (void)testImageHashDetectsCorruption {
  // The invariant GYKeepSync's download path depends on: recomputing the
  // hash over tampered bytes must NOT match the originally declared hash,
  // or corruption/truncation during download would go unnoticed.
  NSData *original = [@"original bytes" dataUsingEncoding:NSUTF8StringEncoding];
  NSData *corrupted = [@"original byteZ" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertNotEqualObjects(GYSHA256Hex(original), GYSHA256Hex(corrupted));
}

- (void)testOversizedImageIsRejectedAtCapture {
  GYBlockStore *store = [self freshStore];
  NSString *sha = [@"" stringByPaddingToLength:64 withString:@"ab" startingAtIndex:0];
  GYBlock *block = [store insertCapturedImageBlockAt:NSDate.date.timeIntervalSince1970
                                              entryId:[self newEntryId]
                                               sha256:sha
                                             byteSize:10 * 1024 * 1024 + 1  // spec §7.3: 10 MiB cap
                                             blobPath:@"/tmp/too-big.png"];
  XCTAssertNil(block, @"a >10 MiB image must be rejected, not silently truncated or accepted");
}

@end
