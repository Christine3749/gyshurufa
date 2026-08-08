#import "GYBlockStore.h"

#import <sqlite3.h>

static NSUInteger const kGYMaxImageBytes = 10 * 1024 * 1024;  // 10 MiB, spec §7.3
static NSUInteger const kGYMaxTextBytes = 1024 * 1024;        // 1 MiB, spec §8.2

@implementation GYBlock
@end

static BOOL GYIsValidEntryId(NSString *entryId) {
  if (![entryId isKindOfClass:NSString.class] || entryId.length < 8 || entryId.length > 128) return NO;
  static NSCharacterSet *disallowed;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    disallowed = [NSCharacterSet characterSetWithCharactersInString:
                      @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"].invertedSet;
  });
  return [entryId rangeOfCharacterFromSet:disallowed].location == NSNotFound;
}

static NSString *GYStateName(GYBlockState state) {
  switch (state) {
    case GYBlockStateQueued: return @"queued";
    case GYBlockStateConfirmed: return @"confirmed";
    case GYBlockStateLocalOnly: return @"local_only";
  }
  return @"queued";
}

static GYBlockState GYStateFromName(NSString *name) {
  if ([name isEqualToString:@"confirmed"]) return GYBlockStateConfirmed;
  if ([name isEqualToString:@"local_only"]) return GYBlockStateLocalOnly;
  return GYBlockStateQueued;
}

@implementation GYBlockStore {
  sqlite3 *_db;
  NSLock *_lock;
  NSString *_deviceId;
}

+ (instancetype)sharedStore {
  static GYBlockStore *store;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ store = [[self alloc] initPrivate]; });
  return store;
}

- (instancetype)init { return [GYBlockStore sharedStore]; }

- (NSURL *)supportDirectory {
  NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                        inDomains:NSUserDomainMask].firstObject;
  NSURL *directory = [support URLByAppendingPathComponent:@"GYInput" isDirectory:YES];
  [NSFileManager.defaultManager createDirectoryAtURL:directory
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:nil];
  return directory;
}

- (instancetype)initPrivate {
  self = [super init];
  if (!self) return nil;
  _lock = [[NSLock alloc] init];
  NSURL *directory = [self supportDirectory];
  NSURL *dbURL = [directory URLByAppendingPathComponent:@"sync.sqlite"];
  [NSFileManager.defaultManager createDirectoryAtURL:[directory URLByAppendingPathComponent:@"blobs" isDirectory:YES]
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:nil];
  if (sqlite3_open(dbURL.fileSystemRepresentation, &_db) != SQLITE_OK) {
    NSLog(@"GY blockstore: failed to open sync.sqlite (%s)", sqlite3_errmsg(_db));
  }
  sqlite3_exec(_db, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);
  sqlite3_exec(_db, "PRAGMA foreign_keys=ON;", NULL, NULL, NULL);
  [self createSchema];
  [self loadOrCreateDeviceId];
  return self;
}

- (void)createSchema {
  const char *sql =
      "CREATE TABLE IF NOT EXISTS blocks ("
      "  entry_id TEXT PRIMARY KEY,"
      "  kind TEXT NOT NULL,"
      "  captured_at REAL NOT NULL,"
      "  state TEXT NOT NULL,"
      "  sequence TEXT,"
      "  origin_device_id TEXT,"
      "  text TEXT,"
      "  byte_size INTEGER NOT NULL DEFAULT 0,"
      "  sha256 TEXT,"
      "  blob_path TEXT,"
      "  local_seq INTEGER"
      ");"
      "CREATE TABLE IF NOT EXISTS outbox ("
      "  entry_id TEXT PRIMARY KEY,"
      "  attempts INTEGER NOT NULL DEFAULT 0,"
      "  next_retry_at REAL NOT NULL DEFAULT 0,"
      "  last_error TEXT"
      ");"
      "CREATE TABLE IF NOT EXISTS sync_state ("
      "  account_id TEXT PRIMARY KEY,"
      "  cursor TEXT NOT NULL DEFAULT '0'"
      ");"
      "CREATE TABLE IF NOT EXISTS tombstones ("
      "  entry_id TEXT PRIMARY KEY,"
      "  sequence TEXT NOT NULL"
      ");"
      "CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT);";
  char *errmsg = NULL;
  if (sqlite3_exec(_db, sql, NULL, NULL, &errmsg) != SQLITE_OK) {
    NSLog(@"GY blockstore: schema create failed (%s)", errmsg);
    sqlite3_free(errmsg);
  }
}

- (void)loadOrCreateDeviceId {
  sqlite3_stmt *stmt = NULL;
  sqlite3_prepare_v2(_db, "SELECT v FROM kv WHERE k='device_id'", -1, &stmt, NULL);
  if (sqlite3_step(stmt) == SQLITE_ROW) {
    const unsigned char *text = sqlite3_column_text(stmt, 0);
    if (text != NULL) _deviceId = [NSString stringWithUTF8String:(const char *)text];
  }
  sqlite3_finalize(stmt);
  if (_deviceId.length == 0 || !GYIsValidEntryId(_deviceId)) {
    _deviceId = [NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    sqlite3_stmt *insert = NULL;
    sqlite3_prepare_v2(_db, "INSERT OR REPLACE INTO kv (k, v) VALUES ('device_id', ?)", -1, &insert, NULL);
    sqlite3_bind_text(insert, 1, _deviceId.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_step(insert);
    sqlite3_finalize(insert);
  }
}

- (NSString *)deviceId {
  [_lock lock];
  NSString *value = _deviceId;
  [_lock unlock];
  return value;
}

// MARK: - Row <-> GYBlock

- (GYBlock *)blockFromStatement:(sqlite3_stmt *)stmt {
  GYBlock *block = [[GYBlock alloc] init];
  block.entryId = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
  NSString *kindName = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
  block.kind = [kindName isEqualToString:@"image"] ? GYBlockKindImage : GYBlockKindText;
  block.capturedAt = sqlite3_column_double(stmt, 2);
  block.state = GYStateFromName([NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 3)]);
  const unsigned char *sequence = sqlite3_column_text(stmt, 4);
  block.sequence = sequence != NULL ? [NSString stringWithUTF8String:(const char *)sequence] : nil;
  const unsigned char *origin = sqlite3_column_text(stmt, 5);
  block.originDeviceId = origin != NULL ? [NSString stringWithUTF8String:(const char *)origin] : nil;
  const unsigned char *text = sqlite3_column_text(stmt, 6);
  block.text = text != NULL ? [NSString stringWithUTF8String:(const char *)text] : nil;
  block.byteSize = (NSUInteger)sqlite3_column_int64(stmt, 7);
  const unsigned char *sha = sqlite3_column_text(stmt, 8);
  block.sha256 = sha != NULL ? [NSString stringWithUTF8String:(const char *)sha] : nil;
  const unsigned char *blob = sqlite3_column_text(stmt, 9);
  block.blobPath = blob != NULL ? [NSString stringWithUTF8String:(const char *)blob] : nil;
  return block;
}

static NSString *const kGYBlockColumns =
    @"entry_id, kind, captured_at, state, sequence, origin_device_id, text, byte_size, sha256, blob_path";

// MARK: - Capture

- (GYBlock *)insertCapturedTextBlock:(NSString *)text capturedAt:(NSTimeInterval)capturedAt entryId:(NSString *)entryId {
  if (text.length == 0 || [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > kGYMaxTextBytes) return nil;
  GYBlock *block = [[GYBlock alloc] init];
  block.entryId = entryId;
  block.kind = GYBlockKindText;
  block.capturedAt = capturedAt;
  block.state = GYBlockStateQueued;
  block.text = text;
  [_lock lock];
  sqlite3_stmt *stmt = NULL;
  sqlite3_prepare_v2(_db,
      "INSERT INTO blocks (entry_id, kind, captured_at, state, text, byte_size, local_seq)"
      " VALUES (?, 'text', ?, 'queued', ?, ?, (SELECT IFNULL(MAX(local_seq),0)+1 FROM blocks))",
      -1, &stmt, NULL);
  sqlite3_bind_text(stmt, 1, entryId.UTF8String, -1, SQLITE_TRANSIENT);
  sqlite3_bind_double(stmt, 2, capturedAt);
  sqlite3_bind_text(stmt, 3, text.UTF8String, -1, SQLITE_TRANSIENT);
  sqlite3_bind_int64(stmt, 4, (sqlite3_int64)[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
  sqlite3_step(stmt);
  sqlite3_finalize(stmt);
  [self insertOutboxRowLocked:entryId];
  [_lock unlock];
  return block;
}

- (GYBlock *)insertCapturedImageBlockAt:(NSTimeInterval)capturedAt
                                entryId:(NSString *)entryId
                                 sha256:(NSString *)sha256
                               byteSize:(NSUInteger)byteSize
                               blobPath:(NSString *)blobPath {
  if (byteSize == 0 || byteSize > kGYMaxImageBytes) return nil;
  GYBlock *block = [[GYBlock alloc] init];
  block.entryId = entryId;
  block.kind = GYBlockKindImage;
  block.capturedAt = capturedAt;
  block.state = GYBlockStateQueued;
  block.sha256 = sha256;
  block.byteSize = byteSize;
  block.blobPath = blobPath;
  [_lock lock];
  sqlite3_stmt *stmt = NULL;
  sqlite3_prepare_v2(_db,
      "INSERT INTO blocks (entry_id, kind, captured_at, state, sha256, byte_size, blob_path, local_seq)"
      " VALUES (?, 'image', ?, 'queued', ?, ?, ?, (SELECT IFNULL(MAX(local_seq),0)+1 FROM blocks))",
      -1, &stmt, NULL);
  sqlite3_bind_text(stmt, 1, entryId.UTF8String, -1, SQLITE_TRANSIENT);
  sqlite3_bind_double(stmt, 2, capturedAt);
  sqlite3_bind_text(stmt, 3, sha256.UTF8String, -1, SQLITE_TRANSIENT);
  sqlite3_bind_int64(stmt, 4, (sqlite3_int64)byteSize);
  sqlite3_bind_text(stmt, 5, blobPath.UTF8String, -1, SQLITE_TRANSIENT);
  sqlite3_step(stmt);
  sqlite3_finalize(stmt);
  [self insertOutboxRowLocked:entryId];
  [_lock unlock];
  return block;
}

/// Caller must hold `_lock`.
- (void)insertOutboxRowLocked:(NSString *)entryId {
  sqlite3_stmt *stmt = NULL;
  sqlite3_prepare_v2(_db, "INSERT OR IGNORE INTO outbox (entry_id) VALUES (?)", -1, &stmt, NULL);
  sqlite3_bind_text(stmt, 1, entryId.UTF8String, -1, SQLITE_TRANSIENT);
  sqlite3_step(stmt);
  sqlite3_finalize(stmt);
}

// MARK: - Views

- (NSArray<GYBlock *> *)headProjectionWithLimit:(NSUInteger)limit {
  [_lock lock];
  NSMutableArray<GYBlock *> *result = [NSMutableArray array];
  NSMutableSet<NSString *> *seen = [NSMutableSet set];

  NSString *unconfirmedSQL = [NSString stringWithFormat:
      @"SELECT %@ FROM blocks WHERE state != 'confirmed' ORDER BY local_seq DESC", kGYBlockColumns];
  sqlite3_stmt *stmt = NULL;
  sqlite3_prepare_v2(_db, unconfirmedSQL.UTF8String, -1, &stmt, NULL);
  while (sqlite3_step(stmt) == SQLITE_ROW && result.count < limit) {
    GYBlock *block = [self blockFromStatement:stmt];
    if ([seen containsObject:block.entryId]) continue;
    [seen addObject:block.entryId];
    [result addObject:block];
  }
  sqlite3_finalize(stmt);

  if (result.count < limit) {
    NSString *confirmedSQL = [NSString stringWithFormat:
        @"SELECT %@ FROM blocks WHERE state = 'confirmed' ORDER BY CAST(sequence AS INTEGER) DESC", kGYBlockColumns];
    sqlite3_prepare_v2(_db, confirmedSQL.UTF8String, -1, &stmt, NULL);
    while (sqlite3_step(stmt) == SQLITE_ROW && result.count < limit) {
      GYBlock *block = [self blockFromStatement:stmt];
      if ([seen containsObject:block.entryId]) continue;
      [seen addObject:block.entryId];
      [result addObject:block];
    }
    sqlite3_finalize(stmt);
  }
  [_lock unlock];
  return result;
}

- (NSArray<GYBlock *> *)pendingOutbox {
  [_lock lock];
  NSMutableArray<GYBlock *> *result = [NSMutableArray array];
  NSString *sql = [NSString stringWithFormat:
      @"SELECT %@ FROM blocks WHERE state != 'confirmed' AND state != 'local_only' ORDER BY local_seq ASC", kGYBlockColumns];
  sqlite3_stmt *stmt = NULL;
  sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
  while (sqlite3_step(stmt) == SQLITE_ROW) [result addObject:[self blockFromStatement:stmt]];
  sqlite3_finalize(stmt);
  [_lock unlock];
  return result;
}

- (nullable GYBlock *)blockForEntryId:(NSString *)entryId {
  [_lock lock];
  NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM blocks WHERE entry_id = ?", kGYBlockColumns];
  sqlite3_stmt *stmt = NULL;
  sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
  sqlite3_bind_text(stmt, 1, entryId.UTF8String, -1, SQLITE_TRANSIENT);
  GYBlock *block = nil;
  if (sqlite3_step(stmt) == SQLITE_ROW) block = [self blockFromStatement:stmt];
  sqlite3_finalize(stmt);
  [_lock unlock];
  return block;
}

// MARK: - Upload outcomes

- (BOOL)acknowledgeEntryId:(NSString *)entryId sequence:(NSString *)sequence {
  if (entryId.length == 0 || sequence.length == 0) return NO;
  [_lock lock];
  sqlite3_exec(_db, "BEGIN IMMEDIATE", NULL, NULL, NULL);
  sqlite3_stmt *stmt = NULL;
  sqlite3_prepare_v2(_db, "UPDATE blocks SET state='confirmed', sequence=? WHERE entry_id=?", -1, &stmt, NULL);
  sqlite3_bind_text(stmt, 1, sequence.UTF8String, -1, SQLITE_TRANSIENT);
  sqlite3_bind_text(stmt, 2, entryId.UTF8String, -1, SQLITE_TRANSIENT);
  sqlite3_step(stmt);
  const BOOL changed = sqlite3_changes(_db) > 0;
  sqlite3_finalize(stmt);
  sqlite3_stmt *del = NULL;
  sqlite3_prepare_v2(_db, "DELETE FROM outbox WHERE entry_id=?", -1, &del, NULL);
  sqlite3_bind_text(del, 1, entryId.UTF8String, -1, SQLITE_TRANSIENT);
  sqlite3_step(del);
  sqlite3_finalize(del);
  sqlite3_exec(_db, "COMMIT", NULL, NULL, NULL);
  [_lock unlock];
  return changed;
}

// MARK: - Remote application

- (void)upsertConfirmedBlockLocked:(GYBlock *)block {
  sqlite3_stmt *stmt = NULL;
  sqlite3_prepare_v2(_db,
      "INSERT INTO blocks (entry_id, kind, captured_at, state, sequence, origin_device_id, text, byte_size, sha256, blob_path, local_seq)"
      " VALUES (?, ?, ?, 'confirmed', ?, ?, ?, ?, ?, ?, (SELECT IFNULL(MAX(local_seq),0)+1 FROM blocks))"
      " ON CONFLICT(entry_id) DO UPDATE SET"
      "   state='confirmed', sequence=excluded.sequence, origin_device_id=excluded.origin_device_id,"
      "   captured_at=excluded.captured_at,"
      "   text=CASE WHEN excluded.kind='text' THEN excluded.text ELSE blocks.text END,"
      "   sha256=CASE WHEN excluded.kind='image' THEN excluded.sha256 ELSE blocks.sha256 END,"
      "   byte_size=CASE WHEN excluded.kind='image' THEN excluded.byte_size ELSE blocks.byte_size END,"
      "   blob_path=CASE WHEN excluded.kind='image' AND blocks.blob_path IS NULL THEN excluded.blob_path ELSE blocks.blob_path END",
      -1, &stmt, NULL);
  sqlite3_bind_text(stmt, 1, block.entryId.UTF8String, -1, SQLITE_TRANSIENT);
  sqlite3_bind_text(stmt, 2, block.kind == GYBlockKindImage ? "image" : "text", -1, SQLITE_TRANSIENT);
  sqlite3_bind_double(stmt, 3, block.capturedAt);
  sqlite3_bind_text(stmt, 4, block.sequence.UTF8String ?: "", -1, SQLITE_TRANSIENT);
  if (block.originDeviceId.length > 0) sqlite3_bind_text(stmt, 5, block.originDeviceId.UTF8String, -1, SQLITE_TRANSIENT);
  else sqlite3_bind_null(stmt, 5);
  if (block.text.length > 0) sqlite3_bind_text(stmt, 6, block.text.UTF8String, -1, SQLITE_TRANSIENT);
  else sqlite3_bind_null(stmt, 6);
  sqlite3_bind_int64(stmt, 7, (sqlite3_int64)block.byteSize);
  if (block.sha256.length > 0) sqlite3_bind_text(stmt, 8, block.sha256.UTF8String, -1, SQLITE_TRANSIENT);
  else sqlite3_bind_null(stmt, 8);
  if (block.blobPath.length > 0) sqlite3_bind_text(stmt, 9, block.blobPath.UTF8String, -1, SQLITE_TRANSIENT);
  else sqlite3_bind_null(stmt, 9);
  sqlite3_step(stmt);
  sqlite3_finalize(stmt);
  // A block that just got its own local upload confirmed may still have an
  // outbox row from a previous attempt; remote confirmation of the same id
  // (another device raced us) must clear it too.
  sqlite3_stmt *del = NULL;
  sqlite3_prepare_v2(_db, "DELETE FROM outbox WHERE entry_id=?", -1, &del, NULL);
  sqlite3_bind_text(del, 1, block.entryId.UTF8String, -1, SQLITE_TRANSIENT);
  sqlite3_step(del);
  sqlite3_finalize(del);
}

- (void)replaceConfirmedSnapshot:(NSArray<GYBlock *> *)blocks {
  [_lock lock];
  sqlite3_exec(_db, "BEGIN IMMEDIATE", NULL, NULL, NULL);
  NSMutableArray<NSString *> *placeholders = [NSMutableArray array];
  for (NSUInteger i = 0; i < blocks.count; ++i) [placeholders addObject:@"?"];
  NSString *keepList = placeholders.count > 0 ? [placeholders componentsJoinedByString:@","] : @"''";
  NSString *deleteSQL = [NSString stringWithFormat:
      @"DELETE FROM blocks WHERE state='confirmed' AND entry_id NOT IN (%@)", keepList];
  sqlite3_stmt *del = NULL;
  sqlite3_prepare_v2(_db, deleteSQL.UTF8String, -1, &del, NULL);
  for (NSUInteger i = 0; i < blocks.count; ++i) {
    sqlite3_bind_text(del, (int)i + 1, blocks[i].entryId.UTF8String, -1, SQLITE_TRANSIENT);
  }
  sqlite3_step(del);
  sqlite3_finalize(del);
  for (GYBlock *block in blocks) [self upsertConfirmedBlockLocked:block];
  sqlite3_exec(_db, "COMMIT", NULL, NULL, NULL);
  [_lock unlock];
}

- (void)applyConfirmedAdd:(GYBlock *)block {
  [_lock lock];
  sqlite3_exec(_db, "BEGIN IMMEDIATE", NULL, NULL, NULL);
  [self upsertConfirmedBlockLocked:block];
  sqlite3_exec(_db, "COMMIT", NULL, NULL, NULL);
  [_lock unlock];
}

- (void)applyDeleteEntryId:(NSString *)entryId {
  [_lock lock];
  sqlite3_exec(_db, "BEGIN IMMEDIATE", NULL, NULL, NULL);
  sqlite3_stmt *stmt = NULL;
  sqlite3_prepare_v2(_db, "DELETE FROM blocks WHERE entry_id=?", -1, &stmt, NULL);
  sqlite3_bind_text(stmt, 1, entryId.UTF8String, -1, SQLITE_TRANSIENT);
  sqlite3_step(stmt);
  sqlite3_finalize(stmt);
  sqlite3_stmt *del = NULL;
  sqlite3_prepare_v2(_db, "DELETE FROM outbox WHERE entry_id=?", -1, &del, NULL);
  sqlite3_bind_text(del, 1, entryId.UTF8String, -1, SQLITE_TRANSIENT);
  sqlite3_step(del);
  sqlite3_finalize(del);
  sqlite3_exec(_db, "COMMIT", NULL, NULL, NULL);
  [_lock unlock];
}

- (void)clearAllBlocks {
  [_lock lock];
  sqlite3_exec(_db, "DELETE FROM outbox", NULL, NULL, NULL);
  sqlite3_exec(_db, "DELETE FROM blocks", NULL, NULL, NULL);
  [_lock unlock];
}

// MARK: - Sync state

- (NSString *)cursorForAccount:(NSString *)accountId {
  [_lock lock];
  sqlite3_stmt *stmt = NULL;
  sqlite3_prepare_v2(_db, "SELECT cursor FROM sync_state WHERE account_id=?", -1, &stmt, NULL);
  sqlite3_bind_text(stmt, 1, accountId.UTF8String ?: "", -1, SQLITE_TRANSIENT);
  NSString *cursor = @"0";
  if (sqlite3_step(stmt) == SQLITE_ROW) {
    const unsigned char *text = sqlite3_column_text(stmt, 0);
    if (text != NULL) cursor = [NSString stringWithUTF8String:(const char *)text];
  }
  sqlite3_finalize(stmt);
  [_lock unlock];
  return cursor;
}

- (void)setCursor:(NSString *)cursor forAccount:(NSString *)accountId {
  [_lock lock];
  sqlite3_stmt *stmt = NULL;
  sqlite3_prepare_v2(_db, "INSERT INTO sync_state (account_id, cursor) VALUES (?, ?)"
                          " ON CONFLICT(account_id) DO UPDATE SET cursor=excluded.cursor",
                     -1, &stmt, NULL);
  sqlite3_bind_text(stmt, 1, accountId.UTF8String ?: "", -1, SQLITE_TRANSIENT);
  sqlite3_bind_text(stmt, 2, cursor.UTF8String ?: "0", -1, SQLITE_TRANSIENT);
  sqlite3_step(stmt);
  sqlite3_finalize(stmt);
  [_lock unlock];
}

- (void)resetCursorForAccount:(NSString *)accountId {
  [self setCursor:@"0" forAccount:accountId];
}

// MARK: - Legacy migration

- (void)migrateLegacyTSVIfNeeded {
  [_lock lock];
  sqlite3_stmt *check = NULL;
  sqlite3_prepare_v2(_db, "SELECT v FROM kv WHERE k='tsv_migrated'", -1, &check, NULL);
  const BOOL alreadyMigrated = sqlite3_step(check) == SQLITE_ROW;
  sqlite3_finalize(check);
  sqlite3_stmt *countStmt = NULL;
  sqlite3_prepare_v2(_db, "SELECT COUNT(*) FROM blocks", -1, &countStmt, NULL);
  sqlite3_step(countStmt);
  const BOOL hasBlocks = sqlite3_column_int64(countStmt, 0) > 0;
  sqlite3_finalize(countStmt);
  [_lock unlock];
  if (alreadyMigrated || hasBlocks) return;

  NSURL *tsvURL = [[self supportDirectory] URLByAppendingPathComponent:@"clipboard-history.tsv"];
  NSString *content = [NSString stringWithContentsOfURL:tsvURL encoding:NSUTF8StringEncoding error:nil];
  NSMutableArray<GYBlock *> *queued = [NSMutableArray array];
  NSMutableArray<GYBlock *> *localOnly = [NSMutableArray array];
  if ([content isKindOfClass:NSString.class]) {
    for (NSString *line in [content componentsSeparatedByString:@"\n"]) {
      if (line.length == 0) continue;
      NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\t"];
      if (fields.count < 4) continue;
      NSString *entryId = GYIsValidEntryId(fields[0])
          ? fields[0]
          : [NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
      NSTimeInterval capturedAt = fields[1].doubleValue;
      BOOL pending = [fields[2] isEqualToString:@"1"];
      NSString *escaped = [[fields subarrayWithRange:NSMakeRange(3, fields.count - 3)] componentsJoinedByString:@"\t"];
      NSMutableString *text = [NSMutableString stringWithCapacity:escaped.length];
      BOOL pendingEscape = NO;
      for (NSUInteger i = 0; i < escaped.length; ++i) {
        unichar ch = [escaped characterAtIndex:i];
        if (!pendingEscape) {
          if (ch == '\\') pendingEscape = YES;
          else [text appendFormat:@"%C", ch];
          continue;
        }
        if (ch == 't') [text appendString:@"\t"];
        else if (ch == 'r') [text appendString:@"\r"];
        else if (ch == 'n') [text appendString:@"\n"];
        else [text appendFormat:@"%C", ch];
        pendingEscape = NO;
      }
      if (text.length == 0) continue;
      GYBlock *block = [[GYBlock alloc] init];
      block.entryId = entryId;
      block.kind = GYBlockKindText;
      block.capturedAt = capturedAt;
      block.text = text;
      if (pending) { block.state = GYBlockStateQueued; [queued addObject:block]; }
      else { block.state = GYBlockStateLocalOnly; [localOnly addObject:block]; }
    }
  }

  [_lock lock];
  sqlite3_exec(_db, "BEGIN IMMEDIATE", NULL, NULL, NULL);
  NSInteger localSeq = 0;
  for (GYBlock *block in [queued arrayByAddingObjectsFromArray:localOnly]) {
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(_db,
        "INSERT OR IGNORE INTO blocks (entry_id, kind, captured_at, state, text, byte_size, local_seq)"
        " VALUES (?, 'text', ?, ?, ?, ?, ?)",
        -1, &stmt, NULL);
    sqlite3_bind_text(stmt, 1, block.entryId.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 2, block.capturedAt);
    sqlite3_bind_text(stmt, 3, GYStateName(block.state).UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, block.text.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 5, (sqlite3_int64)[block.text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
    sqlite3_bind_int64(stmt, 6, ++localSeq);
    sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (block.state == GYBlockStateQueued) [self insertOutboxRowLocked:block.entryId];
  }
  sqlite3_stmt *mark = NULL;
  sqlite3_prepare_v2(_db, "INSERT OR REPLACE INTO kv (k, v) VALUES ('tsv_migrated', ?)", -1, &mark, NULL);
  sqlite3_bind_text(mark, 1, [[NSDate.date description] UTF8String], -1, SQLITE_TRANSIENT);
  sqlite3_step(mark);
  sqlite3_finalize(mark);
  sqlite3_exec(_db, "COMMIT", NULL, NULL, NULL);
  [_lock unlock];

  if (queued.count + localOnly.count > 0) {
    NSURL *backupURL = [[self supportDirectory] URLByAppendingPathComponent:@"clipboard-history.tsv.migrated-backup"];
    [NSFileManager.defaultManager removeItemAtURL:backupURL error:nil];
    [NSFileManager.defaultManager moveItemAtURL:tsvURL toURL:backupURL error:nil];
    NSLog(@"GY blockstore: migrated %lu queued + %lu local-only rows from legacy TSV",
          (unsigned long)queued.count, (unsigned long)localOnly.count);
  }
}

@end
