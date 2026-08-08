#import "GYKeepSync.h"
#import "GYAccountAuth.h"
#import "GYBlockStore.h"
#import "GYClipboardHistory.h"
#import "GYSettingsStore.h"
#import "GYSyncWire.h"

#import <unistd.h>

static NSString *const kKeepBase = @"https://keep.gyenbox.com";
static NSString *const kSyncPath = @"/api/clipboard/sync";
static NSString *const kImagePathPrefix = @"/api/clipboard/images/";
// This class never appends `?format=wire-v4` — every GET below is v3-only,
// which is confirmed live and is what Windows 0.10.79 sends too (see the
// NAMING note in GYSyncWire.h). GYSyncWire already has a tested v4 parser
// and GYSyncFormatNegotiation already has the tested rule for when it would
// be safe to start requesting v4 (authenticated 200 + response actually
// v4-shaped; auto-downgrade if the server ignores the parameter; never flip
// on a 401/404/503). Neither is wired into the request path here yet — that
// is a live-behavior change deferred to once a real, authenticated probe
// confirms v4 is actually enabled on the deployed revision, not something
// to flip alongside the parser/negotiation logic itself.
// Windows 0.10.79 polls every 750ms and only backs off to 5s once its SSE
// wake channel is confirmed available (MACOS-SESSION-HANDOFF-20260808.md).
// keep.gyenbox.com does not have /api/clipboard/stream deployed yet (probed
// 2026-08-08: 404), so Windows itself is at the 750ms rate right now — Mac
// matches that baseline rather than the old 3s interval to stay at parity.
static const NSTimeInterval kPollInterval = 0.75;
static const NSTimeInterval kRequestTimeout = 20;
static const NSInteger kMaxPagesPerRound = 8;

static NSString *GYLocalDeviceName(void) {
  char host[256] = {0};
  if (gethostname(host, sizeof(host) - 1) != 0 || host[0] == '\0') return @"Mac";
  NSString *name = [NSString stringWithUTF8String:host];
  NSRange dot = [name rangeOfString:@"."];
  return dot.location == NSNotFound ? name : [name substringToIndex:dot.location];
}

@implementation GYKeepSync {
  dispatch_queue_t _queue;
  dispatch_source_t _timer;
  NSURLSession *_session;
  BOOL _syncing;
  /// The one entryId this device does not need to re-apply to the system
  /// pasteboard — either because it just uploaded it (own copy, already on
  /// the pasteboard) or because it already wrote that remote HEAD once.
  /// Mirrors the Windows client's single `g_last_handled_head_id`.
  NSString *_lastHandledHeadId;
  /// NO until the first successful pull. Unlike Windows (which will paste
  /// Keep's current HEAD immediately on a cold start), Mac deliberately does
  /// not do that — the first pull only records where Keep is, so login never
  /// silently overwrites whatever the user already has copied. This guard
  /// predates this rewrite; kept intentionally (see MEMORY: don't remove
  /// clipboard-protection gates without confirming with the user first).
  BOOL _hasSeededHead;
  /// Set when 「复制即粘贴」 is switched back on, so the current head lands
  /// once even though it is not new.
  BOOL _forcePublishNextHead;
}

+ (instancetype)sharedSync {
  static GYKeepSync *sync;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ sync = [[self alloc] initPrivate]; });
  return sync;
}

- (instancetype)init { return [GYKeepSync sharedSync]; }

- (instancetype)initPrivate {
  self = [super init];
  if (!self) return nil;
  _queue = dispatch_queue_create("wang.shurufa.GYInput.keepsync", DISPATCH_QUEUE_SERIAL);
  NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
  configuration.HTTPShouldSetCookies = NO;
  configuration.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
  configuration.timeoutIntervalForRequest = kRequestTimeout;
  _session = [NSURLSession sessionWithConfiguration:configuration];
  return self;
}

- (void)start {
  if (_timer != nil) return;
  [GYAccountAuth.sharedAuth restoreSessionIfNeeded];
  [NSNotificationCenter.defaultCenter addObserver:self
                                         selector:@selector(localHistoryDidChange:)
                                             name:GYClipboardHistory.didChangeNotification
                                           object:nil];
  _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
  dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPollInterval * NSEC_PER_SEC)),
                            (uint64_t)(kPollInterval * NSEC_PER_SEC), (uint64_t)(NSEC_PER_SEC / 10));
  __weak typeof(self) weakSelf = self;
  dispatch_source_set_event_handler(_timer, ^{ [weakSelf runRound]; });
  dispatch_resume(_timer);
}

- (void)localHistoryDidChange:(NSNotification *)notification {
  (void)notification;
  [self wake];
}

- (void)wake {
  __weak typeof(self) weakSelf = self;
  dispatch_async(_queue, ^{ [weakSelf runRound]; });
}

- (void)setEnabled:(BOOL)enabled {
  GYSettingsStore.sharedStore.clipboardSyncEnabled = enabled;
  if (enabled) [self wake];
}

- (void)setInstantPasteEnabled:(BOOL)enabled {
  GYSettingsStore.sharedStore.clipboardInstantPaste = enabled;
  __weak typeof(self) weakSelf = self;
  dispatch_async(_queue, ^{
    typeof(self) self_ = weakSelf;
    if (self_ == nil) return;
    if (enabled) {
      self_->_lastHandledHeadId = nil;
      self_->_forcePublishNextHead = YES;
    } else {
      self_->_forcePublishNextHead = NO;
    }
    [self_ runRound];
  });
}

- (void)accountDidChange {
  __weak typeof(self) weakSelf = self;
  dispatch_async(_queue, ^{
    typeof(self) self_ = weakSelf;
    if (self_ == nil) return;
    self_->_lastHandledHeadId = nil;
    self_->_hasSeededHead = NO;
    self_->_forcePublishNextHead = NO;
    [self_ runRound];
  });
}

// MARK: - One round

/// Always on `_queue`.
- (void)runRound {
  if (_syncing) return;
  if (!GYSettingsStore.sharedStore.clipboardSyncEnabled) return;
  if (GYAccountAuth.sharedAuth.status != GYAccountStatusLoggedIn) return;
  _syncing = YES;

  __weak typeof(self) weakSelf = self;
  [GYAccountAuth.sharedAuth accessTokenWithCompletion:^(NSString *token) {
    typeof(self) self_ = weakSelf;
    if (self_ == nil) return;
    NSString *accountId = GYAccountAuth.sharedAuth.email ?: @"";
    dispatch_async(self_->_queue, ^{
      if (token == nil) {  // signed out, or the network is down; retry next tick
        self_->_syncing = NO;
        return;
      }
      [self_ roundWithToken:token accountId:accountId];
    });
  }];
}

/// Always on `_queue`.
- (void)roundWithToken:(NSString *)token accountId:(NSString *)accountId {
  NSArray<GYBlock *> *pending = [GYBlockStore.sharedStore pendingOutbox];
  __weak typeof(self) weakSelf = self;
  [self uploadPending:pending
                index:0
                token:token
           completion:^{
             typeof(self) self_ = weakSelf;
             if (self_ == nil) return;
             NSString *cursor = [GYBlockStore.sharedStore cursorForAccount:accountId];
             // A pending repair (see GYBlockStore.h needsSnapshotForAccount:)
             // forces a snapshot fetch regardless of cursor — a prior
             // round's DELETE recovery that failed (network, image hash,
             // crash) must retry as a snapshot, not resume incremental
             // cursor paging, or the exposed HEAD-20 gap never gets filled.
             const BOOL needsSnapshot = [GYBlockStore.sharedStore needsSnapshotForAccount:accountId];
             const BOOL snapshot = needsSnapshot || cursor.length == 0 || [cursor isEqualToString:@"0"];
             [self_ pullPageWithToken:token
                             accountId:accountId
                                cursor:cursor
                              snapshot:snapshot
                             pagesLeft:kMaxPagesPerRound];
           }];
}

// MARK: - Upload (Outbox drain)

/// Uploads oldest-first. A failed entry is skipped (retried next round) so
/// it never blocks the entries behind it — the one deliberate divergence
/// from the Windows client, which aborts the whole round on the first
/// failure; skip-and-continue is strictly more robust and was already the
/// documented Mac behavior before this rewrite. Always continues on `_queue`.
- (void)uploadPending:(NSArray<GYBlock *> *)pending
                index:(NSUInteger)index
                token:(NSString *)token
           completion:(dispatch_block_t)completion {
  if (index >= pending.count) {
    completion();
    return;
  }
  GYBlock *block = pending[index];
  if (block.kind == GYBlockKindImage) {
    [self uploadImageBlock:block token:token completion:^(BOOL stopRound) {
      if (stopRound) { completion(); return; }
      [self uploadPending:pending index:index + 1 token:token completion:completion];
    }];
  } else {
    [self uploadTextBlock:block token:token completion:^(BOOL stopRound) {
      if (stopRound) { completion(); return; }
      [self uploadPending:pending index:index + 1 token:token completion:completion];
    }];
  }
}

- (void)uploadTextBlock:(GYBlock *)block token:(NSString *)token completion:(void (^)(BOOL stopRound))completion {
  NSData *textData = [block.text dataUsingEncoding:NSUTF8StringEncoding];
  if (textData == nil) { completion(NO); return; }
  NSData *body = [NSJSONSerialization dataWithJSONObject:@{
    @"id": block.entryId,
    @"textBase64": [textData base64EncodedStringWithOptions:0],
    @"capturedAt": @((long long)llround(block.capturedAt * 1000)),
  } options:0 error:nil];
  NSMutableURLRequest *request = [self requestWithMethod:@"POST" path:kSyncPath token:token];
  request.HTTPBody = body;
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
  [self sendAckRequest:request forEntryId:block.entryId completion:completion];
}

- (void)uploadImageBlock:(GYBlock *)block token:(NSString *)token completion:(void (^)(BOOL stopRound))completion {
  NSData *pngData = block.blobPath.length > 0 ? [NSData dataWithContentsOfFile:block.blobPath] : nil;
  if (pngData == nil) { completion(NO); return; }  // blob missing: skip, nothing to retry productively
  NSString *path = [NSString stringWithFormat:@"%@%@?format=ack-v3", kImagePathPrefix, block.entryId];
  NSMutableURLRequest *request = [self requestWithMethod:@"PUT" path:path token:token];
  request.HTTPBody = pngData;
  [request setValue:@"image/png" forHTTPHeaderField:@"Content-Type"];
  [request setValue:[NSString stringWithFormat:@"%lld", (long long)llround(block.capturedAt * 1000)]
      forHTTPHeaderField:@"X-GY-Captured-At"];
  [request setValue:block.sha256 forHTTPHeaderField:@"X-GY-SHA256"];
  [self sendAckRequest:request forEntryId:block.entryId completion:completion];
}

- (void)sendAckRequest:(NSURLRequest *)request forEntryId:(NSString *)entryId completion:(void (^)(BOOL stopRound))completion {
  __weak typeof(self) weakSelf = self;
  [[_session dataTaskWithRequest:request
               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                 typeof(self) self_ = weakSelf;
                 if (self_ == nil) return;
                 const NSInteger code = ((NSHTTPURLResponse *)response).statusCode;
                 const BOOL accepted = error == nil && (code == 200 || code == 201);
                 NSString *sequence = accepted ? GYParseAckSequence(data) : nil;
                 if (!accepted) NSLog(@"GY keep: upload rejected (HTTP %ld)", (long)code);
                 dispatch_async(self_->_queue, ^{
                   if (accepted && sequence != nil) {
                     [GYBlockStore.sharedStore acknowledgeEntryId:entryId sequence:sequence];
                     self_->_lastHandledHeadId = entryId;
                     completion(NO);
                   } else if (error == nil && code == 401) {
                     // Token died mid-round. Stop here; the next round
                     // refreshes it and the entry is still pending.
                     completion(YES);
                   } else {
                     // Failed or malformed ack: stays pending, retried next round.
                     completion(NO);
                   }
                 });
               }] resume];
}

// MARK: - Pull (snapshot / cursor)

/// Always continues on `_queue`.
- (void)pullPageWithToken:(NSString *)token
                accountId:(NSString *)accountId
                   cursor:(NSString *)cursor
                 snapshot:(BOOL)snapshot
                pagesLeft:(NSInteger)pagesLeft {
  if (pagesLeft <= 0) {
    [self maybeRepairThenFinalizeToken:token accountId:accountId];
    return;
  }
  NSString *path = snapshot ? [kSyncPath stringByAppendingString:@"?snapshot=1"]
                             : [NSString stringWithFormat:@"%@?cursor=%@", kSyncPath, cursor];
  NSMutableURLRequest *request = [self requestWithMethod:@"GET" path:path token:token];
  __weak typeof(self) weakSelf = self;
  [[_session dataTaskWithRequest:request
               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                 typeof(self) self_ = weakSelf;
                 if (self_ == nil) return;
                 const NSInteger code = ((NSHTTPURLResponse *)response).statusCode;
                 NSString *nextCursor = nil;
                 NSNumber *hasMore = nil;
                 NSArray<GYWireChange *> *changes = nil;
                 if (error == nil && code == 200 && data != nil) {
                   changes = GYParseSyncPage(data, &nextCursor, &hasMore);
                 }
                 NSLog(@"GY keep: pull HTTP %ld → %lu changes, %lu bytes", (long)code,
                       (unsigned long)changes.count, (unsigned long)data.length);
                 dispatch_async(self_->_queue, ^{
                   if (changes == nil || nextCursor == nil) {
                     // Abort round; retried next tick from the same cursor.
                     // If this fetch was itself the repair snapshot,
                     // needsSnapshot was never cleared, so it will be
                     // retried as a snapshot again, not lost as incremental
                     // cursor paging resumes.
                     self_->_syncing = NO;
                     return;
                   }
                   [self_ downloadImagesForChanges:changes
                                              token:token
                                         completion:^(BOOL imagesOk) {
                     if (!imagesOk) { self_->_syncing = NO; return; }  // same retry guarantee as above
                     [self_ applyChanges:changes snapshot:snapshot];
                     // Order matters: a DELETE's repair flag must be durably
                     // set BEFORE the cursor advances past it. If the app
                     // dies between these two lines, the flag is already
                     // true on disk — the cursor write below never executes
                     // without the flag write having already committed.
                     if (!snapshot) {
                       for (GYWireChange *change in changes) {
                         if (change.kind == GYWireChangeDelete) {
                           [GYBlockStore.sharedStore setNeedsSnapshot:YES forAccount:accountId];
                           break;
                         }
                       }
                     }
                     [GYBlockStore.sharedStore setCursor:nextCursor forAccount:accountId];
                     // This fetch WAS the repair snapshot and it just fully
                     // succeeded (parsed, images verified, applied, cursor
                     // moved) — only now is the gap actually filled.
                     if (snapshot) [GYBlockStore.sharedStore setNeedsSnapshot:NO forAccount:accountId];
                     if (!hasMore.boolValue || [nextCursor isEqualToString:cursor]) {
                       [self_ maybeRepairThenFinalizeToken:token accountId:accountId];
                       return;
                     }
                     [self_ pullPageWithToken:token
                                     accountId:accountId
                                        cursor:nextCursor
                                      snapshot:NO
                                     pagesLeft:pagesLeft - 1];
                   }];
                 });
               }] resume];
}

/// A DELETE can expose a 21st confirmed item that was previously hidden
/// behind the HEAD-20 view; one authoritative snapshot fills that slot.
/// Called after the round's normal incremental paging finishes — re-reads
/// GYBlockStore's durable needsSnapshot flag (not an in-memory parameter)
/// rather than the round's own `sawDelete` history, so this correctly picks
/// up BOTH a delete seen just now AND a repair a previous round left
/// unfinished (crash, network failure, image hash mismatch). If this
/// round's own fetch already was the repair snapshot, the flag was already
/// cleared on success, so this is a no-op — no redundant fetch. Always
/// continues on `_queue`.
- (void)maybeRepairThenFinalizeToken:(NSString *)token accountId:(NSString *)accountId {
  if (![GYBlockStore.sharedStore needsSnapshotForAccount:accountId]) {
    [self finalizeRound];
    return;
  }
  NSMutableURLRequest *request = [self requestWithMethod:@"GET" path:[kSyncPath stringByAppendingString:@"?snapshot=1"] token:token];
  __weak typeof(self) weakSelf = self;
  [[_session dataTaskWithRequest:request
               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                 typeof(self) self_ = weakSelf;
                 if (self_ == nil) return;
                 const NSInteger code = ((NSHTTPURLResponse *)response).statusCode;
                 NSString *nextCursor = nil;
                 NSNumber *hasMore = nil;
                 NSArray<GYWireChange *> *changes = nil;
                 if (error == nil && code == 200 && data != nil) changes = GYParseSyncPage(data, &nextCursor, &hasMore);
                 dispatch_async(self_->_queue, ^{
                   if (changes == nil || nextCursor == nil) {
                     // Repair failed: flag stays set (never cleared), so the
                     // very next round retries the snapshot fetch instead of
                     // resuming incremental cursor paging that would never
                     // see this DELETE again.
                     self_->_syncing = NO;
                     return;
                   }
                   [self_ downloadImagesForChanges:changes
                                              token:token
                                         completion:^(BOOL imagesOk) {
                     if (!imagesOk) { self_->_syncing = NO; return; }  // same retry guarantee as above
                     [self_ applyChanges:changes snapshot:YES];
                     [GYBlockStore.sharedStore setCursor:nextCursor forAccount:accountId];
                     // Only clear now that fetch, image verification, store
                     // update, and cursor advance have ALL succeeded.
                     [GYBlockStore.sharedStore setNeedsSnapshot:NO forAccount:accountId];
                     [self_ finalizeRound];
                   }];
                 });
               }] resume];
}

- (void)downloadImagesForChanges:(NSArray<GYWireChange *> *)changes
                            token:(NSString *)token
                       completion:(void (^)(BOOL ok))completion {
  NSMutableArray<GYBlock *> *imageAdds = [NSMutableArray array];
  for (GYWireChange *change in changes) {
    if (change.kind == GYWireChangeAdd && change.block.kind == GYBlockKindImage) [imageAdds addObject:change.block];
  }
  [self downloadImages:imageAdds index:0 token:token completion:completion];
}

- (void)downloadImages:(NSArray<GYBlock *> *)imageBlocks
                 index:(NSUInteger)index
                 token:(NSString *)token
            completion:(void (^)(BOOL ok))completion {
  if (index >= imageBlocks.count) { completion(YES); return; }
  GYBlock *pending = imageBlocks[index];
  NSURL *blobURL = [[self blobDirectory] URLByAppendingPathComponent:[pending.entryId stringByAppendingPathExtension:@"png"]];
  NSData *existing = [NSData dataWithContentsOfURL:blobURL];
  if (existing.length > 0 && [GYSHA256Hex(existing) isEqualToString:pending.sha256]) {
    pending.blobPath = blobURL.path;
    [self downloadImages:imageBlocks index:index + 1 token:token completion:completion];
    return;
  }
  NSString *path = [kImagePathPrefix stringByAppendingString:pending.entryId];
  NSMutableURLRequest *request = [self requestWithMethod:@"GET" path:path token:token];
  [request setValue:@"image/png" forHTTPHeaderField:@"Accept"];
  __weak typeof(self) weakSelf = self;
  [[_session dataTaskWithRequest:request
               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                 typeof(self) self_ = weakSelf;
                 if (self_ == nil) return;
                 const NSInteger code = ((NSHTTPURLResponse *)response).statusCode;
                 const BOOL valid = error == nil && code == 200 && data.length > 0 && data.length <= 10 * 1024 * 1024 &&
                                    [GYSHA256Hex(data) isEqualToString:pending.sha256];
                 dispatch_async(self_->_queue, ^{
                   if (!valid) {
                     NSLog(@"GY keep: image download/hash mismatch for %@ (HTTP %ld)", pending.entryId, (long)code);
                     completion(NO);
                     return;
                   }
                   if ([data writeToURL:blobURL atomically:YES]) pending.blobPath = blobURL.path;
                   [self_ downloadImages:imageBlocks index:index + 1 token:token completion:completion];
                 });
               }] resume];
}

- (void)applyChanges:(NSArray<GYWireChange *> *)changes snapshot:(BOOL)snapshot {
  if (snapshot) {
    NSMutableArray<GYBlock *> *adds = [NSMutableArray array];
    for (GYWireChange *change in changes) if (change.kind == GYWireChangeAdd) [adds addObject:change.block];
    [GYBlockStore.sharedStore replaceConfirmedSnapshot:adds];
    return;
  }
  for (GYWireChange *change in changes) {
    if (change.kind == GYWireChangeAdd) [GYBlockStore.sharedStore applyConfirmedAdd:change.block];
    else [GYBlockStore.sharedStore applyDeleteEntryId:change.entryId];
  }
}

/// Always on `_queue`.
- (void)finalizeRound {
  GYClipboardEntry *head = GYClipboardHistory.sharedHistory.entries.firstObject;
  if (head != nil && !head.pendingUpload) {
    const BOOL unhandled = _lastHandledHeadId == nil || ![head.entryId isEqualToString:_lastHandledHeadId];
    const BOOL allowed = GYSettingsStore.sharedStore.clipboardInstantPaste && unhandled &&
                          (_hasSeededHead || _forcePublishNextHead);
    if (allowed) {
      BOOL applied;
      if (head.kind == GYBlockKindImage) {
        NSData *imageData = [GYClipboardHistory.sharedHistory imageDataForEntry:head];
        applied = imageData != nil && [GYClipboardHistory.sharedHistory publishRemoteImageToSystemPasteboard:imageData];
      } else {
        applied = [GYClipboardHistory.sharedHistory publishRemoteTextToSystemPasteboard:head.text];
      }
      if (applied) {
        _lastHandledHeadId = head.entryId;
        _forcePublishNextHead = NO;
      }
    }
    if (!_hasSeededHead) {
      _hasSeededHead = YES;
      if (_lastHandledHeadId == nil) _lastHandledHeadId = head.entryId;  // seed without pasting
    }
  }
  _syncing = NO;
}

// MARK: - HTTP plumbing

- (NSURL *)blobDirectory {
  NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                        inDomains:NSUserDomainMask].firstObject;
  return [[support URLByAppendingPathComponent:@"GYInput" isDirectory:YES] URLByAppendingPathComponent:@"blobs" isDirectory:YES];
}

- (NSMutableURLRequest *)requestWithMethod:(NSString *)method path:(NSString *)path token:(NSString *)token {
  NSURL *url = [NSURL URLWithString:[kKeepBase stringByAppendingString:path]];
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  request.HTTPMethod = method;
  request.HTTPShouldHandleCookies = NO;
  request.timeoutInterval = kRequestTimeout;
  [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
  [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
  [request setValue:GYBlockStore.sharedStore.deviceId forHTTPHeaderField:@"X-GY-Device-ID"];
  [request setValue:GYLocalDeviceName() forHTTPHeaderField:@"X-GY-Device-Name"];
  return request;
}

@end
