#import "GYRimeBridge.h"

#if __has_include(<rime_api.h>)
#define GY_HAS_RIME 1
#include <rime_api.h>
#include <opencc/opencc.h>
#else
#error "GY Input requires the staged arm64 librime SDK. Run scripts/bootstrap-rime-arm64.sh first."
#endif

static void GYInitializeRimeOnce(RimeApi *api, RimeTraits *traits) {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    api->setup(traits);
    api->initialize(traits);
  });
}

static BOOL GYEnsureBundledWorkspace(NSURL *sharedDataURL, NSURL *userDataURL, NSString **diagnostic) {
  NSURL *source = [sharedDataURL URLByAppendingPathComponent:@"build" isDirectory:YES];
  NSURL *destination = [userDataURL URLByAppendingPathComponent:@"build" isDirectory:YES];
  NSURL *deployedSchema = [destination URLByAppendingPathComponent:@"luna_pinyin.schema.yaml"];
  NSURL *sourceMarker = [sharedDataURL URLByAppendingPathComponent:@"workspace.version"];
  NSURL *destinationMarker = [userDataURL URLByAppendingPathComponent:@".gyinput-workspace-version"];
  NSString *sourceVersion = [NSString stringWithContentsOfURL:sourceMarker encoding:NSUTF8StringEncoding error:nil];
  NSString *deployedVersion = [NSString stringWithContentsOfURL:destinationMarker encoding:NSUTF8StringEncoding error:nil];
  BOOL needsDeployment = ![NSFileManager.defaultManager fileExistsAtPath:deployedSchema.path] ||
      sourceVersion.length == 0 || ![sourceVersion isEqualToString:deployedVersion];
  if (!needsDeployment) return YES;

  NSError *error = nil;
  if (![NSFileManager.defaultManager createDirectoryAtURL:destination withIntermediateDirectories:YES attributes:nil error:&error]) {
    if (diagnostic != NULL) *diagnostic = [NSString stringWithFormat:@"cannot create Rime user workspace: %@", error.localizedDescription];
    return NO;
  }
  NSArray<NSString *> *files = @[@"default.yaml", @"luna_pinyin.prism.bin", @"luna_pinyin.reverse.bin", @"luna_pinyin.schema.yaml", @"luna_pinyin.table.bin"];
  for (NSString *file in files) {
    NSURL *from = [source URLByAppendingPathComponent:file];
    NSURL *to = [destination URLByAppendingPathComponent:file];
    if (![NSFileManager.defaultManager fileExistsAtPath:from.path]) {
      if (diagnostic != NULL) *diagnostic = [NSString stringWithFormat:@"bundled Rime workspace is missing %@", file];
      return NO;
    }
    error = nil;
    if ([NSFileManager.defaultManager fileExistsAtPath:to.path] &&
        ![NSFileManager.defaultManager removeItemAtURL:to error:&error]) {
      if (diagnostic != NULL) *diagnostic = [NSString stringWithFormat:@"cannot replace Rime workspace %@: %@", file, error.localizedDescription];
      return NO;
    }
    error = nil;
    if (![NSFileManager.defaultManager copyItemAtURL:from toURL:to error:&error]) {
      if (diagnostic != NULL) *diagnostic = [NSString stringWithFormat:@"cannot deploy Rime workspace: %@", error.localizedDescription];
      return NO;
    }
  }
  if (sourceVersion.length != 0 && ![sourceVersion writeToURL:destinationMarker atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
    if (diagnostic != NULL) *diagnostic = [NSString stringWithFormat:@"cannot write Rime workspace version: %@", error.localizedDescription];
    return NO;
  }
  return YES;
}

static NSURL *GYDefaultUserDataURL(void) {
  NSURL *support = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                           inDomains:NSUserDomainMask] firstObject];
  return [[support URLByAppendingPathComponent:@"GYInput" isDirectory:YES]
                   URLByAppendingPathComponent:@"rime" isDirectory:YES];
}

#if GY_HAS_RIME
static BOOL GYOpenCCIsValid(opencc_t converter) {
  return converter != NULL && converter != (opencc_t)-1;
}
#endif

@interface GYRimeBridge ()
- (BOOL)moveToCandidatePage:(NSUInteger)pageNumber;
@end

@implementation GYRimeBridge {
  NSURL *_sharedDataURL;
  NSURL *_userDataURL;
  NSString *_diagnostic;
#if GY_HAS_RIME
  RimeApi *_api;
  RimeSessionId _session;
  NSUInteger _currentPageNumber;
  BOOL _canPageUp;
  BOOL _canPageDown;
  NSString *_compositionCode;
  opencc_t _simplifiedConverter;
  opencc_t _traditionalConverter;
#endif
}

- (instancetype)initWithSharedDataURL:(NSURL *)sharedDataURL
                           userDataURL:(NSURL *)userDataURL {
  self = [super init];
  if (!self) return nil;
  _sharedDataURL = sharedDataURL;
  _userDataURL = userDataURL;
#if GY_HAS_RIME
#if GY_HAS_RIME
  NSString *workspaceError = nil;
  if (sharedDataURL == nil || !GYEnsureBundledWorkspace(sharedDataURL, userDataURL, &workspaceError)) {
    _diagnostic = workspaceError ?: @"bundled Rime workspace is unavailable";
    return self;
  }
#endif
  const char *sharedPath = sharedDataURL.path.UTF8String;
  const char *userPath = userDataURL.path.UTF8String;
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = sharedPath;
  traits.user_data_dir = userPath;
  traits.distribution_name = "GY Input Method";
  traits.distribution_code_name = "gyinput-macos";
  traits.distribution_version = "0.9.17";
  traits.app_name = "rime.gyinput.macos";
  traits.min_log_level = 2;
  _api = rime_get_api();
  if (_api == nullptr) {
    _diagnostic = @"rime_get_api returned null";
    return self;
  }
  GYInitializeRimeOnce(_api, &traits);
  _session = _api->create_session();
  if (_session == 0 || !_api->select_schema(_session, "luna_pinyin")) {
    _diagnostic = @"librime could not create a luna_pinyin session";
    return self;
  }
  [self setInputMode:GYInputModeSimplified];
  _diagnostic = @"ready";
#else
  _diagnostic = @"librime arm64 has not been staged; run the M1 Rime build before testing input";
#endif
  return self;
}

- (void)dealloc {
#if GY_HAS_RIME
  if (GYOpenCCIsValid(_simplifiedConverter)) opencc_close(_simplifiedConverter);
  if (GYOpenCCIsValid(_traditionalConverter)) opencc_close(_traditionalConverter);
  if (_api != nullptr && _session != 0) _api->destroy_session(_session);
#endif
}

- (BOOL)isReady {
#if GY_HAS_RIME
  return _api != nullptr && _session != 0;
#else
  return NO;
#endif
}

- (NSString *)diagnostic { return _diagnostic ?: @"not initialized"; }

- (void)setInputMode:(GYInputMode)mode {
#if GY_HAS_RIME
  if (![self isReady]) return;
  _api->set_option(_session, "ascii_mode", mode == GYInputModeEnglish ? True : False);
  _api->set_option(_session, "zh_hans", mode == GYInputModeSimplified ? True : False);
#else
  (void)mode;
#endif
}

- (NSArray<NSString *> *)candidatesForCode:(NSString *)code {
#if GY_HAS_RIME
  if (![self isReady] || code.length == 0) return @[];
  _api->clear_composition(_session);
  _currentPageNumber = 0;
  _canPageUp = NO;
  _canPageDown = NO;
  const char *keys = code.UTF8String;
  for (const unsigned char *key = (const unsigned char *)keys; key != nullptr && *key != 0; ++key) {
    if (!_api->process_key(_session, *key, 0)) {
      _compositionCode = nil;
      return @[];
    }
  }
  _compositionCode = [code copy];
  return [self currentCandidates];
#else
  (void)code;
  return @[];
#endif
}

- (NSArray<NSString *> *)currentCandidates {
#if GY_HAS_RIME
  if (![self isReady]) return @[];
  RIME_STRUCT(RimeContext, context);
  if (!_api->get_context(_session, &context)) return @[];
  _currentPageNumber = MAX(0, context.menu.page_no);
  _canPageUp = context.menu.page_no > 0;
  _canPageDown = context.menu.is_last_page == False;
  NSMutableArray<NSString *> *result = [NSMutableArray array];
  for (size_t i = 0; i < context.menu.num_candidates; ++i) {
    const char *text = context.menu.candidates[i].text;
    if (text != nullptr) [result addObject:[NSString stringWithUTF8String:text]];
  }
  _api->free_context(&context);
  return result;
#else
  return @[];
#endif
}

- (NSString *)localCandidateForPhrase:(NSString *)phrase inputMode:(GYInputMode)mode {
#if GY_HAS_RIME
  if (phrase.length == 0 || mode == GYInputModeEnglish || _sharedDataURL == nil) return phrase;
  // `t2s` accepts a source phrase in either script and makes the simplified
  // mode deterministic; `s2t` does the inverse for the traditional mode.
  NSString *configName = mode == GYInputModeTraditional ? @"s2t.json" : @"t2s.json";
  opencc_t *converter = mode == GYInputModeTraditional ? &_traditionalConverter : &_simplifiedConverter;
  if (!GYOpenCCIsValid(*converter)) {
    NSURL *config = [_sharedDataURL URLByAppendingPathComponent:[@"opencc" stringByAppendingPathComponent:configName]];
    *converter = opencc_open(config.path.UTF8String);
    if (!GYOpenCCIsValid(*converter)) {
      *converter = NULL;
      return phrase;
    }
  }
  char *converted = opencc_convert_utf8(*converter, phrase.UTF8String, (size_t)-1);
  if (converted == NULL) return phrase;
  NSString *result = [[NSString alloc] initWithUTF8String:converted];
  opencc_convert_utf8_free(converted);
  return result.length == 0 ? phrase : result;
#else
  (void)mode;
  return phrase;
#endif
}

- (NSUInteger)currentPageNumber {
#if GY_HAS_RIME
  return _currentPageNumber;
#else
  return 0;
#endif
}

- (BOOL)canPageUp {
#if GY_HAS_RIME
  return _canPageUp;
#else
  return NO;
#endif
}

- (BOOL)canPageDown {
#if GY_HAS_RIME
  return _canPageDown;
#else
  return NO;
#endif
}

- (nullable NSString *)commitCandidateAtIndex:(NSUInteger)index {
#if GY_HAS_RIME
  if (![self isReady] || !_api->select_candidate_on_current_page(_session, (size_t)index)) return nil;
  RIME_STRUCT(RimeCommit, commit);
  if (!_api->get_commit(_session, &commit) || commit.text == nullptr) return nil;
  NSString *result = [NSString stringWithUTF8String:commit.text];
  _api->free_commit(&commit);
  return result;
#else
  (void)index;
  return nil;
#endif
}

- (void)clearComposition {
#if GY_HAS_RIME
  if ([self isReady]) _api->clear_composition(_session);
  _compositionCode = nil;
  _currentPageNumber = 0;
  _canPageUp = NO;
  _canPageDown = NO;
#endif
}

- (nullable NSString *)commitCandidateAtPage:(NSUInteger)pageNumber index:(NSUInteger)index {
#if GY_HAS_RIME
  if (![self moveToCandidatePage:pageNumber]) return nil;
  return [self commitCandidateAtIndex:index];
#else
  (void)pageNumber;
  (void)index;
  return nil;
#endif
}

+ (BOOL)moveLearningDatabaseToTrash:(NSError * _Nullable * _Nullable)error {
  NSURL *database = [GYDefaultUserDataURL() URLByAppendingPathComponent:@"luna_pinyin.userdb" isDirectory:YES];
  if (![NSFileManager.defaultManager fileExistsAtPath:database.path]) return YES;
  return [NSFileManager.defaultManager trashItemAtURL:database resultingItemURL:nil error:error];
}

// Rime's backward paging depends on its internal highlighted-candidate
// cursor.  That cursor can be stale after an expanded 5 × 5 panel redraw,
// which made the visible ↓ pager work while ↑ appeared inert.  Replaying the
// very small pinyin composition and paging forward to the requested page is
// deterministic and leaves Rime on the exact page used for later selection.
- (BOOL)moveToCandidatePage:(NSUInteger)pageNumber {
#if GY_HAS_RIME
  if (![self isReady] || _compositionCode.length == 0) return NO;
  NSString *code = [_compositionCode copy];
  [self candidatesForCode:code];
  for (NSUInteger page = 0; page < pageNumber; ++page) {
    if (!_api->change_page(_session, False)) return NO;
    (void)[self currentCandidates];
  }
  return _currentPageNumber == pageNumber;
#else
  (void)pageNumber;
  return NO;
#endif
}


- (BOOL)pageUp {
#if GY_HAS_RIME
  if (![self isReady] || _currentPageNumber == 0) return NO;
  return [self moveToCandidatePage:_currentPageNumber - 1];
#else
  return NO;
#endif
}

- (BOOL)pageDown {
#if GY_HAS_RIME
  return [self isReady] && _api->change_page(_session, False);
#else
  return NO;
#endif
}
@end
