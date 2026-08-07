#import "GYKeepSync.h"
#import "GYAccountAuth.h"
#import "GYClipboardHistory.h"
#import "GYSettingsStore.h"

static NSString *const kKeepBase = @"https://keep.gyenbox.com";
static NSString *const kClipboardPath = @"/api/clipboard?format=wire";
static const NSTimeInterval kPollInterval = 3;
static const NSTimeInterval kRequestTimeout = 20;

/// One wire line: `<id>\t<capturedAt ms>\t<base64 text>`, newest first.
static NSArray<GYClipboardEntry *> *GYParseWirePayload(NSString *_Nullable base64Payload) {
  NSData *decoded = base64Payload.length == 0
                        ? nil
                        : [[NSData alloc] initWithBase64EncodedString:base64Payload
                                                              options:NSDataBase64DecodingIgnoreUnknownCharacters];
  NSString *body = decoded == nil ? nil : [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
  if (body.length == 0) return @[];
  NSMutableArray<GYClipboardEntry *> *entries = [NSMutableArray array];
  for (NSString *line in [body componentsSeparatedByString:@"\n"]) {
    if (line.length == 0) continue;
    NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\t"];
    if (fields.count < 3) continue;
    NSData *textData = [[NSData alloc] initWithBase64EncodedString:fields[2]
                                                           options:NSDataBase64DecodingIgnoreUnknownCharacters];
    NSString *text = textData == nil ? nil : [[NSString alloc] initWithData:textData encoding:NSUTF8StringEncoding];
    if (text.length == 0) continue;
    GYClipboardEntry *entry = [[GYClipboardEntry alloc] init];
    entry.entryId = fields[0];
    entry.text = text;
    entry.unixTime = fields[1].doubleValue / 1000.0;  // wire 用毫秒，本机存秒
    entry.pendingUpload = NO;
    [entries addObject:entry];
  }
  return entries;
}

@implementation GYKeepSync {
  dispatch_queue_t _queue;
  dispatch_source_t _timer;
  NSURLSession *_session;
  BOOL _syncing;
  /// Newest remote entry this Mac has already written to the pasteboard.
  NSString *_lastAppliedRemoteHeadId;
  /// NO until the first successful pull. The first pull only records where
  /// Keep is; it must not overwrite whatever the user already has copied.
  BOOL _hasSeededRemoteHead;
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
                            (uint64_t)(kPollInterval * NSEC_PER_SEC), (uint64_t)(NSEC_PER_SEC / 2));
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
      self_->_lastAppliedRemoteHeadId = nil;
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
    self_->_lastAppliedRemoteHeadId = nil;
    self_->_hasSeededRemoteHead = NO;
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
    dispatch_async(self_->_queue, ^{
      if (token == nil) { // signed out, or the network is down; retry next tick
        self_->_syncing = NO;
        return;
      }
      [self_ roundWithToken:token];
    });
  }];
}

/// Always on `_queue`.
- (void)roundWithToken:(NSString *)token {
  GYClipboardHistory *history = GYClipboardHistory.sharedHistory;
  NSArray<GYClipboardEntry *> *localBefore = history.entries;
  // Captured before the merge: if Keep's newest entry is the one this Mac just
  // uploaded, it is already "here" and must not be written back to the
  // pasteboard — that write is what would clobber a screenshot.
  NSString *preMergeLocalHeadId = localBefore.firstObject.entryId;

  NSMutableArray<GYClipboardEntry *> *pending = [NSMutableArray array];
  for (GYClipboardEntry *entry in [localBefore reverseObjectEnumerator]) { // oldest first
    if (entry.pendingUpload) [pending addObject:entry];
  }

  __weak typeof(self) weakSelf = self;
  [self uploadPending:pending
                index:0
                token:token
           completion:^{
             typeof(self) self_ = weakSelf;
             if (self_ == nil) return;
             [self_ pullWithToken:token
                       localAfter:history.entries
              preMergeLocalHeadId:preMergeLocalHeadId];
           }];
}

/// Uploads oldest-first, one at a time, so Keep's ordering matches the order
/// the user actually copied. Always continues on `_queue`.
- (void)uploadPending:(NSArray<GYClipboardEntry *> *)pending
                index:(NSUInteger)index
                token:(NSString *)token
           completion:(dispatch_block_t)completion {
  if (index >= pending.count) {
    completion();
    return;
  }
  GYClipboardEntry *entry = pending[index];
  NSData *textData = [entry.text dataUsingEncoding:NSUTF8StringEncoding];
  NSMutableURLRequest *request = [self requestWithMethod:@"POST" token:token];
  request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{
    @"id": entry.entryId,
    @"textBase64": [textData base64EncodedStringWithOptions:0],
    @"capturedAt": @((long long)llround(entry.unixTime * 1000)),
  }
                                                    options:0
                                                      error:nil];
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

  __weak typeof(self) weakSelf = self;
  [[_session dataTaskWithRequest:request
               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                 (void)data;
                 typeof(self) self_ = weakSelf;
                 if (self_ == nil) return;
                 const NSInteger code = ((NSHTTPURLResponse *)response).statusCode;
                 const BOOL accepted = error == nil && (code == 200 || code == 201);
                 dispatch_async(self_->_queue, ^{
                   if (accepted) {
                     entry.pendingUpload = NO;
                   } else if (error == nil && code == 401) {
                     // Token died mid-round. Stop here; the next round
                     // refreshes it and the entry is still pending.
                     completion();
                     return;
                   }
                   // A failed upload stays pending and is retried next round,
                   // but must not block the entries behind it.
                   [self_ uploadPending:pending index:index + 1 token:token completion:completion];
                 });
               }] resume];
}

/// Always continues on `_queue`.
- (void)pullWithToken:(NSString *)token
           localAfter:(NSArray<GYClipboardEntry *> *)localAfter
  preMergeLocalHeadId:(NSString *_Nullable)preMergeLocalHeadId {
  NSMutableURLRequest *request = [self requestWithMethod:@"GET" token:token];
  __weak typeof(self) weakSelf = self;
  [[_session dataTaskWithRequest:request
               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                 typeof(self) self_ = weakSelf;
                 if (self_ == nil) return;
                 const NSInteger code = ((NSHTTPURLResponse *)response).statusCode;
                 NSArray<GYClipboardEntry *> *remote = nil;
                 if (error == nil && code >= 200 && code <= 299 && data != nil) {
                   id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                   NSDictionary *envelope = [json isKindOfClass:NSDictionary.class] ? json : nil;
                   NSDictionary *payload = [envelope[@"data"] isKindOfClass:NSDictionary.class] ? envelope[@"data"] : envelope;
                   id base64Payload = payload[@"payload"];
                   remote = GYParseWirePayload([base64Payload isKindOfClass:NSString.class] ? base64Payload : nil);
                 }
                 dispatch_async(self_->_queue, ^{
                   if (remote == nil) {
                     // Pull failed: still persist the upload flags cleared above
                     // so a restart does not re-send everything.
                     [GYClipboardHistory.sharedHistory replaceEntries:localAfter];
                     self_->_syncing = NO;
                     return;
                   }
                   [self_ applyRemote:remote
                                local:localAfter
                  preMergeLocalHeadId:preMergeLocalHeadId];
                   self_->_syncing = NO;
                 });
               }] resume];
}

/// Always on `_queue`.
- (void)applyRemote:(NSArray<GYClipboardEntry *> *)remote
              local:(NSArray<GYClipboardEntry *> *)local
preMergeLocalHeadId:(NSString *_Nullable)preMergeLocalHeadId {
  NSMutableSet<NSString *> *remoteIds = [NSMutableSet setWithCapacity:remote.count];
  for (GYClipboardEntry *entry in remote) [remoteIds addObject:entry.entryId];

  // Anything copied on this Mac while the requests were in flight has not
  // reached Keep yet; keep it at the head so a copy is never lost.
  NSMutableArray<GYClipboardEntry *> *merged = [NSMutableArray array];
  for (GYClipboardEntry *entry in local) {
    if (entry.pendingUpload && ![remoteIds containsObject:entry.entryId]) [merged addObject:entry];
  }
  [merged addObjectsFromArray:remote];
  [GYClipboardHistory.sharedHistory replaceEntries:merged];

  GYClipboardEntry *head = remote.firstObject;
  if (head == nil) return;
  const BOOL isOwnHead = preMergeLocalHeadId != nil && [head.entryId isEqualToString:preMergeLocalHeadId];
  const BOOL alreadyApplied = _lastAppliedRemoteHeadId != nil && [head.entryId isEqualToString:_lastAppliedRemoteHeadId];
  const BOOL isNewRemoteHead = _hasSeededRemoteHead && !isOwnHead && !alreadyApplied;

  if (GYSettingsStore.sharedStore.clipboardInstantPaste && (_forcePublishNextHead || isNewRemoteHead)) {
    if ([GYClipboardHistory.sharedHistory publishRemoteTextToSystemPasteboard:head.text]) {
      _lastAppliedRemoteHeadId = head.entryId;
      _forcePublishNextHead = NO;
    }
  }
  if (!_hasSeededRemoteHead) {
    _hasSeededRemoteHead = YES;
    if (_lastAppliedRemoteHeadId == nil) _lastAppliedRemoteHeadId = head.entryId;
  }
}

- (NSMutableURLRequest *)requestWithMethod:(NSString *)method token:(NSString *)token {
  NSURL *url = [NSURL URLWithString:[kKeepBase stringByAppendingString:kClipboardPath]];
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  request.HTTPMethod = method;
  request.HTTPShouldHandleCookies = NO;
  request.timeoutInterval = kRequestTimeout;
  [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
  [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
  return request;
}

@end
