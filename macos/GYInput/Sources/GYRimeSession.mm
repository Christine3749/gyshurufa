#import "GYRimeSession.h"
#import "GYRimeRuntime.h"

static const int GYRimeBackspace = 0xff08;
static const int GYRimePageUp = 0xff55;
static const int GYRimePageDown = 0xff56;

static NSString *GYString(const char *value) { return value ? [[NSString alloc] initWithUTF8String:value] ?: @"" : @""; }

static BOOL GYAcceptableCandidate(NSString *text) {
  if (text.length == 0 || text.length > 12) return NO;
  for (NSUInteger index = 0; index < text.length; index++) {
    unichar c = [text characterAtIndex:index];
    if (!((c >= 0x3400 && c <= 0x4DBF) || (c >= 0x4E00 && c <= 0x9FFF) || (c >= 0xF900 && c <= 0xFAFF))) return NO;
  }
  return YES;
}

@implementation GYRimeSession {
  GYRimeRuntime *_runtime;
  RimeSessionId _session;
  NSString *_preedit;
  NSString *_commitText;
  NSArray<NSString *> *_candidates;
  NSArray<NSNumber *> *_rawIndices;
  BOOL _hasNextPage;
  BOOL _hasPreviousPage;
  NSInteger _page;
  GYInputMode _mode;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _runtime = GYRimeRuntime.sharedRuntime;
    _preedit = @""; _commitText = @""; _candidates = @[]; _rawIndices = @[];
    _mode = GYInputModeSimplified;
    @synchronized (_runtime) {
      if (_runtime.ready) {
        _session = _runtime.api->create_session();
        if (_session && !_runtime.api->select_schema(_session, "gy_pinyin")) {
          _runtime.api->destroy_session(_session); _session = 0;
        }
      }
    }
  }
  return self;
}

- (void)dealloc {
  @synchronized (_runtime) { if (_session && _runtime.ready) _runtime.api->destroy_session(_session); }
}

- (BOOL)ready { return _session != 0 && _runtime.ready; }
- (NSString *)preedit { return _preedit; }
- (NSString *)commitText { return _commitText; }
- (NSArray<NSString *> *)candidates { return _candidates; }
- (BOOL)hasNextPage { return _hasNextPage; }
- (BOOL)hasPreviousPage { return _hasPreviousPage; }

- (void)setModeLocked:(GYInputMode)mode api:(RimeApi *)api {
  _mode = mode;
  api->set_option(_session, "ascii_mode", False);
  api->set_option(_session, "zh_hans", mode == GYInputModeSimplified ? True : False);
}

- (void)readCommitLocked:(RimeApi *)api {
  RIME_STRUCT(RimeCommit, commit);
  if (api->get_commit(_session, &commit)) {
    _commitText = GYString(commit.text);
    api->free_commit(&commit);
  }
}

- (void)refreshLocked:(RimeApi *)api {
  RIME_STRUCT(RimeContext, context);
  if (!api->get_context(_session, &context)) { _preedit = @""; _candidates = @[]; return; }
  _preedit = GYString(context.composition.preedit);
  _page = context.menu.page_no;
  _hasPreviousPage = _page > 0;
  _hasNextPage = !context.menu.is_last_page;
  NSMutableArray *candidates = [NSMutableArray array];
  NSMutableArray *indices = [NSMutableArray array];
  for (int index = 0; index < context.menu.num_candidates; index++) {
    NSString *candidate = GYString(context.menu.candidates[index].text);
    if (GYAcceptableCandidate(candidate) && ![candidates containsObject:candidate]) {
      [candidates addObject:candidate]; [indices addObject:@(index)];
    }
  }
  _candidates = candidates; _rawIndices = indices;
  api->free_context(&context);
}

- (BOOL)processText:(NSString *)text mode:(GYInputMode)mode {
  if (!self.ready || text.length == 0) return NO;
  @synchronized (_runtime) {
    _commitText = @""; [self setModeLocked:mode api:_runtime.api];
    const char *bytes = text.UTF8String;
    for (const unsigned char *key = (const unsigned char *)bytes; key && *key; key++) {
      if (!_runtime.api->process_key(_session, *key, 0)) return NO;
      [self readCommitLocked:_runtime.api];
    }
    [self refreshLocked:_runtime.api];
  }
  return YES;
}

- (BOOL)deleteBackward {
  if (!self.ready) return NO;
  @synchronized (_runtime) {
    _commitText = @"";
    BOOL handled = _runtime.api->process_key(_session, GYRimeBackspace, 0);
    [self readCommitLocked:_runtime.api]; [self refreshLocked:_runtime.api];
    return handled;
  }
}

- (void)clear {
  @synchronized (_runtime) {
    if (_session && _runtime.ready) _runtime.api->clear_composition(_session);
    _preedit = @""; _commitText = @""; _candidates = @[]; _rawIndices = @[]; _hasNextPage = _hasPreviousPage = NO;
  }
}

- (BOOL)turnPageWithKey:(int)key {
  if (!self.ready) return NO;
  @synchronized (_runtime) {
    NSInteger oldPage = _page;
    _runtime.api->process_key(_session, key, 0); [self refreshLocked:_runtime.api];
    return _page != oldPage;
  }
}

- (BOOL)nextPage { return [self turnPageWithKey:GYRimePageDown]; }
- (BOOL)previousPage { return [self turnPageWithKey:GYRimePageUp]; }

- (BOOL)selectCandidateAtIndex:(NSInteger)index {
  if (!self.ready || index < 0 || (NSUInteger)index >= _rawIndices.count) return NO;
  @synchronized (_runtime) {
    _commitText = @"";
    BOOL selected = _runtime.api->select_candidate_on_current_page(_session, _rawIndices[(NSUInteger)index].unsignedIntegerValue);
    [self readCommitLocked:_runtime.api]; [self refreshLocked:_runtime.api];
    return selected;
  }
}

- (BOOL)commitDefault {
  if (_candidates.count) return [self selectCandidateAtIndex:0];
  return [self processText:@" " mode:_mode];
}

@end

BOOL GYRunRimeSelfTest(void) {
  GYRimeSession *session = [GYRimeSession new];
  if (!session.ready || ![session processText:@"nihao" mode:GYInputModeSimplified]) return NO;
  if (![session.candidates containsObject:@"你好"]) return NO;
  [session clear];
  if (![session processText:@"zhongguo" mode:GYInputModeTraditional]) return NO;
  return [session.candidates containsObject:@"中國"];
}
