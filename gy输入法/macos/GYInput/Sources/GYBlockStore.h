// GYBlockStore — SQLite-backed source of truth for the Keep v4 sync model
// (MACOS-KEEP-IMPLEMENTATION-SPEC.md §3). Replaces clipboard-history.tsv as
// the reliable Outbox: the 20-entry HEAD projection is a *view*, never the
// storage limit, so an offline streak past 20 copies no longer loses data.
//
// Thread-safety: every method takes an internal lock and is safe to call from
// any queue. Callers on the Rime/candidate/composition path must still never
// call this synchronously — capture and sync both already hop off that path.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GYBlockKind) {
  GYBlockKindText,
  GYBlockKindImage,
};

typedef NS_ENUM(NSInteger, GYBlockState) {
  /// Captured locally, not yet uploaded (or upload failed and will retry).
  GYBlockStateQueued,
  /// Keep has ACKed this block; `sequence` is authoritative.
  GYBlockStateConfirmed,
  /// Migrated from the old TSV model with unknown server state. Never
  /// re-uploaded automatically — it is superseded by the first real
  /// snapshot pull and ages out of the HEAD-20 view on its own.
  GYBlockStateLocalOnly,
};

@interface GYBlock : NSObject
@property(nonatomic, copy) NSString *entryId;
@property(nonatomic) GYBlockKind kind;
@property(nonatomic) NSTimeInterval capturedAt;
@property(nonatomic) GYBlockState state;
/// Decimal string. Only Keep assigns this; nil until confirmed. Never store
/// this in a floating-point type — 64-bit sequence values lose precision.
@property(nonatomic, copy, nullable) NSString *sequence;
@property(nonatomic, copy, nullable) NSString *originDeviceId;
/// kind == GYBlockKindText.
@property(nonatomic, copy, nullable) NSString *text;
/// kind == GYBlockKindImage.
@property(nonatomic) NSUInteger byteSize;
@property(nonatomic, copy, nullable) NSString *sha256;
@property(nonatomic, copy, nullable) NSString *blobPath;
@end

@interface GYBlockStore : NSObject

+ (instancetype)sharedStore;

/// For tests only: opens (or creates) a store at an arbitrary file path
/// instead of the app's Application Support singleton. Each call opens a
/// fresh sqlite3 connection, so two instances pointed at the same path can
/// simulate "quit app, relaunch app" for restart-recovery tests. The running
/// app never calls this — only `sharedStore`.
+ (instancetype)storeAtPath:(NSString *)path;

// MARK: Capture (queued, unconfirmed)

- (GYBlock *)insertCapturedTextBlock:(NSString *)text
                            capturedAt:(NSTimeInterval)capturedAt
                              entryId:(NSString *)entryId;

- (GYBlock *)insertCapturedImageBlockAt:(NSTimeInterval)capturedAt
                                entryId:(NSString *)entryId
                                 sha256:(NSString *)sha256
                               byteSize:(NSUInteger)byteSize
                               blobPath:(NSString *)blobPath;

// MARK: Views

/// Local unconfirmed/local-only blocks (newest capture first) merged with
/// Keep-confirmed blocks (highest sequence first), deduped by entryId,
/// capped at `limit`. This is the only "HEAD 20" formula — see spec §3.
- (NSArray<GYBlock *> *)headProjectionWithLimit:(NSUInteger)limit;

/// Every block not yet confirmed, oldest-capture first — the reliable
/// Outbox. Never capped; a long offline streak just makes this list long.
- (NSArray<GYBlock *> *)pendingOutbox;

- (nullable GYBlock *)blockForEntryId:(NSString *)entryId;

// MARK: Upload outcomes

/// One transaction: state -> confirmed, sequence set, still present for the
/// HEAD projection. Idempotent — acknowledging an already-confirmed id with
/// the same sequence is a no-op.
- (BOOL)acknowledgeEntryId:(NSString *)entryId sequence:(NSString *)sequence;

// MARK: Remote application (GET /api/clipboard/sync)

/// Full-state replace for a snapshot page: every confirmed block not present
/// in `blocks` is removed; every block in `blocks` is upserted as confirmed.
/// Queued/local-only rows are untouched — they are this device's own outbox,
/// not part of the server's confirmed set.
- (void)replaceConfirmedSnapshot:(NSArray<GYBlock *> *)blocks;

/// Incremental ADD from a cursor page: upsert as confirmed.
- (void)applyConfirmedAdd:(GYBlock *)block;

/// Incremental DELETE from a cursor page: removes the block (if present).
- (void)applyDeleteEntryId:(NSString *)entryId;

/// Wipes every local block (queued, local_only, and confirmed) and its
/// outbox rows. Mirrors the pre-v4 「清空」 button: Keep is untouched, and the
/// next successful sync round repopulates the view from the server. Anything
/// still queued and not yet uploaded is lost, matching prior behavior.
- (void)clearAllBlocks;

// MARK: Sync state (per logged-in account; "" = logged out / local identity)

- (NSString *)cursorForAccount:(NSString *)accountId;
- (void)setCursor:(NSString *)cursor forAccount:(NSString *)accountId;
- (void)resetCursorForAccount:(NSString *)accountId;

/// Durable "a DELETE exposed a slot that still needs an authoritative
/// snapshot to fill — see spec §7.4" flag. GYKeepSync sets this the moment
/// it applies a page containing a DELETE, strictly before it advances the
/// cursor past that page — so even a crash, a failed network request, or a
/// 500 partway through the repair snapshot leaves this durably set in
/// SQLite rather than only in an in-memory flag that a dropped connection
/// or relaunch would silently lose. Only cleared once a repair snapshot's
/// fetch, image verification, and store update have ALL succeeded.
- (BOOL)needsSnapshotForAccount:(NSString *)accountId;
- (void)setNeedsSnapshot:(BOOL)needsSnapshot forAccount:(NSString *)accountId;

/// Stable per-install device id (URL-safe, 8–128 chars). Generated once and
/// persisted; never changes across launches or re-logins.
@property(nonatomic, readonly, copy) NSString *deviceId;

// MARK: One-time legacy migration

/// Reads the old `<id>\t<unix_ts>\t<pending>\t<escaped>` TSV once. Rows that
/// were still pending upload become `queued` (they were never confirmed
/// under the old model, so re-POSTing them is correct and, per the v4
/// contract, idempotent). Rows that looked already-synced become
/// `local_only`: shown locally but never re-uploaded, so migration can never
/// create a duplicate on Keep. They fall out of the HEAD-20 view on their
/// own once the first real snapshot arrives. No-ops if already migrated or
/// if the TSV does not exist.
- (void)migrateLegacyTSVIfNeeded;

@end

NS_ASSUME_NONNULL_END
