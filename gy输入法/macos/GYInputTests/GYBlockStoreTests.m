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

#pragma mark - 旧 TSV → SQLite → 首次 Keep snapshot 迁移

// Regression test for a review finding: headProjectionWithLimit used to put
// ALL non-confirmed blocks (queued AND local_only) in one tier ahead of
// confirmed data. A migrated local_only row — explicitly documented as
// "never re-uploaded, ages out on its own once the first real snapshot
// arrives" — could therefore permanently occupy a HEAD-20 slot ahead of
// Keep's real, authoritative order, contradicting "Keep is truth" (spec
// §3), because the unconfirmed tier alone could already fill `limit` before
// confirmed rows ever got a turn.
//
// This exercises the real path end to end: writes an actual legacy TSV,
// calls migrateLegacyTSVIfNeeded (not a shortcut through the block-insert
// API), then simulates the very first Keep snapshot arriving.
- (void)testMigratedLocalOnlyRowsYieldToFirstConfirmedSnapshot {
  NSString *tsvPath = [self.tempDirectory stringByAppendingPathComponent:@"clipboard-history.tsv"];
  NSMutableString *tsv = [NSMutableString string];
  NSMutableArray<NSString *> *localOnlyIds = [NSMutableArray array];
  // 25 "already synced under the old model" rows -- pending=0 -> local_only.
  // More than the HEAD-20 cap, so before the fix these alone would already
  // fill the entire view.
  for (NSUInteger i = 0; i < 25; ++i) {
    NSString *entryId = [self newEntryId];
    [localOnlyIds addObject:entryId];
    [tsv appendFormat:@"%@\t%f\t0\told local entry %lu\n", entryId, NSDate.date.timeIntervalSince1970 - (25 - i),
                       (unsigned long)i];
  }
  XCTAssertTrue([tsv writeToFile:tsvPath atomically:YES encoding:NSUTF8StringEncoding error:nil]);

  NSString *dbPath = [self.tempDirectory stringByAppendingPathComponent:@"sync.sqlite"];
  GYBlockStore *store = [GYBlockStore storeAtPath:dbPath];
  [store migrateLegacyTSVIfNeeded];

  // Sanity: migration actually ran and classified these as local_only, not
  // queued -- they must never be silently re-uploaded (that would create
  // duplicates on Keep, which spec explicitly forbids for migration).
  for (NSString *entryId in localOnlyIds) {
    GYBlock *migrated = [store blockForEntryId:entryId];
    XCTAssertEqual(migrated.state, GYBlockStateLocalOnly);
  }
  XCTAssertEqual(store.pendingOutbox.count, (NSUInteger)0, @"local_only rows must never enter the upload outbox");

  // Before any Keep data exists, the migrated rows are all there is --
  // that's fine and expected.
  XCTAssertEqual([store headProjectionWithLimit:20].count, (NSUInteger)20);

  // Now the first real Keep snapshot arrives (exactly what GYKeepSync does
  // on cursor="0" / first login) with 20 confirmed entries -- Keep's real,
  // authoritative order.
  NSMutableArray<GYBlock *> *confirmed = [NSMutableArray array];
  NSMutableArray<NSString *> *confirmedIds = [NSMutableArray array];
  for (NSUInteger i = 0; i < 20; ++i) {
    NSString *entryId = [self newEntryId];
    [confirmedIds addObject:entryId];
    [confirmed addObject:[self confirmedTextBlockWithId:entryId
                                                 sequence:[NSString stringWithFormat:@"%lu", (unsigned long)(i + 1)]
                                                     text:[NSString stringWithFormat:@"keep entry %lu", (unsigned long)i]]];
  }
  [store replaceConfirmedSnapshot:confirmed];

  NSArray<GYBlock *> *headAfterSnapshot = [store headProjectionWithLimit:20];
  XCTAssertEqual(headAfterSnapshot.count, (NSUInteger)20);
  NSArray<NSString *> *headIds = [headAfterSnapshot valueForKey:@"entryId"];
  for (NSString *entryId in confirmedIds) {
    XCTAssertTrue([headIds containsObject:entryId], @"every confirmed entry must be in the HEAD-20 view");
  }
  for (NSString *entryId in localOnlyIds) {
    XCTAssertFalse([headIds containsObject:entryId],
                    @"once 20 real confirmed entries exist, no migrated local_only row may still occupy a slot");
  }
}

- (void)testMigratedLocalOnlyRowsStillFillGapsWhenConfirmedCountIsSmall {
  // If Keep's real history is SHORTER than 20, migrated local_only rows
  // should still fill the remaining slots -- they are a legitimate lowest-
  // priority fallback, not something to hide unconditionally.
  NSString *tsvPath = [self.tempDirectory stringByAppendingPathComponent:@"clipboard-history.tsv"];
  NSString *localOnlyId = [self newEntryId];
  NSString *tsv = [NSString stringWithFormat:@"%@\t%f\t0\tonly local entry\n", localOnlyId, NSDate.date.timeIntervalSince1970];
  XCTAssertTrue([tsv writeToFile:tsvPath atomically:YES encoding:NSUTF8StringEncoding error:nil]);

  NSString *dbPath = [self.tempDirectory stringByAppendingPathComponent:@"sync.sqlite"];
  GYBlockStore *store = [GYBlockStore storeAtPath:dbPath];
  [store migrateLegacyTSVIfNeeded];

  NSString *confirmedId = [self newEntryId];
  [store replaceConfirmedSnapshot:@[ [self confirmedTextBlockWithId:confirmedId sequence:@"1" text:@"from keep"] ]];

  NSArray<NSString *> *headIds = [[store headProjectionWithLimit:20] valueForKey:@"entryId"];
  XCTAssertTrue([headIds containsObject:confirmedId]);
  XCTAssertTrue([headIds containsObject:localOnlyId], @"with room to spare, the local_only fallback should still show");
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

#pragma mark - 大序号排序 (sequence ordering beyond int64)

// Review finding: headProjectionWithLimit used to order confirmed rows via
// `ORDER BY CAST(sequence AS INTEGER)`. SQLite integers are 64-bit signed
// (max ~9.22e18, 19 digits); GYIsDecimalSequence allows up to 20 digits, so
// a sequence at the high end of what the protocol itself considers valid
// could silently overflow the cast and misorder. Fixed to
// `ORDER BY LENGTH(sequence), sequence`, which correctly orders
// non-negative decimal integers of arbitrary size as long as there is no
// leading zero (enforced by GYIsDecimalSequence — see GYSyncWireTests).
- (void)testSequenceOrderingSurvivesValuesBeyondInt64Range {
  GYBlockStore *store = [self freshStore];
  // int64 max is 9223372036854775807 (19 digits). These two are both valid
  // per GYIsDecimalSequence (<=20 digits, no leading zero) and both exceed
  // it -- exactly the range where CAST(sequence AS INTEGER) could silently
  // overflow.
  NSString *huge = @"99999999999999999999";           // 20 digits, all 9s
  NSString *hugeButSmaller = @"88888888888888888888"; // 20 digits, all 8s: numerically and lexicographically smaller
  NSString *smallId = [self newEntryId];
  NSString *hugeId = [self newEntryId];
  [store applyConfirmedAdd:[self confirmedTextBlockWithId:smallId sequence:@"5" text:@"small"]];
  [store applyConfirmedAdd:[self confirmedTextBlockWithId:hugeId sequence:huge text:@"huge"]];
  NSString *middleId = [self newEntryId];
  [store applyConfirmedAdd:[self confirmedTextBlockWithId:middleId sequence:hugeButSmaller text:@"huge but smaller"]];

  NSArray<GYBlock *> *head = [store headProjectionWithLimit:20];
  NSArray<NSString *> *orderedIds = [head valueForKey:@"entryId"];
  // Expected numeric order, highest sequence first: huge > hugeButSmaller > small(5).
  NSUInteger hugeIndex = [orderedIds indexOfObject:hugeId];
  NSUInteger middleIndex = [orderedIds indexOfObject:middleId];
  NSUInteger smallIndex = [orderedIds indexOfObject:smallId];
  XCTAssertTrue(hugeIndex < middleIndex, @"a 20-digit sequence must still outrank another 20-digit sequence correctly");
  XCTAssertTrue(middleIndex < smallIndex, @"any 20-digit sequence must outrank a short one -- this is exactly what "
                @"CAST(...AS INTEGER) could get wrong via silent overflow");
}

- (void)testSequenceOrderingManyDigitLengths {
  // Broader sanity sweep across very different digit lengths, since the
  // LENGTH-then-lexicographic trick's correctness specifically depends on
  // comparing lengths first.
  GYBlockStore *store = [self freshStore];
  NSDictionary<NSString *, NSString *> *sequenceToId = @{
    @"9": [self newEntryId],
    @"10": [self newEntryId],
    @"99": [self newEntryId],
    @"100": [self newEntryId],
    @"12345678901234567": [self newEntryId],   // 17 digits
    @"9999999999999999999": [self newEntryId], // 19 digits, > the 17-digit one
  };
  for (NSString *sequence in sequenceToId) {
    [store applyConfirmedAdd:[self confirmedTextBlockWithId:sequenceToId[sequence] sequence:sequence text:sequence]];
  }
  NSArray<NSString *> *orderedIds = [[store headProjectionWithLimit:20] valueForKey:@"entryId"];
  NSArray<NSString *> *expectedDescending = @[
    sequenceToId[@"9999999999999999999"],
    sequenceToId[@"12345678901234567"],
    sequenceToId[@"100"],
    sequenceToId[@"99"],
    sequenceToId[@"10"],
    sequenceToId[@"9"],
  ];
  XCTAssertEqualObjects(orderedIds, expectedDescending);
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
