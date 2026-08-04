#import "GYRimeBridge.h"

#if __has_include(<rime_api.h>)
#define GY_HAS_RIME 1
#include <rime_api.h>
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
  if ([NSFileManager.defaultManager fileExistsAtPath:deployedSchema.path]) return YES;

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
    if (![NSFileManager.defaultManager copyItemAtURL:from toURL:to error:&error]) {
      if (diagnostic != NULL) *diagnostic = [NSString stringWithFormat:@"cannot deploy Rime workspace: %@", error.localizedDescription];
      return NO;
    }
  }
  return YES;
}

// Candidate governance gate (WINDOWS-DESIGN.md §6): pure CJK ideographs,
// at most 12 characters; emoji, PUA, symbols and duplicates are filtered.
static BOOL GYIsQualityCandidate(NSString *text) {
  if (text.length == 0 || text.length > 12) return NO;
  for (NSUInteger i = 0; i < text.length; ++i) {
    const unichar c = [text characterAtIndex:i];
    const BOOL isCJK = (c >= 0x4E00 && c <= 0x9FFF) ||
                       (c >= 0x3400 && c <= 0x4DBF) ||
                       (c >= 0xF900 && c <= 0xFAFF);
    if (!isCJK) return NO;
  }
  return YES;
}

@implementation GYRimeBridge {
  NSURL *_sharedDataURL;
  NSURL *_userDataURL;
  NSString *_diagnostic;
  // Maps a filtered candidate index (what the user sees) to the raw Rime
  // index (what select_candidate_on_current_page expects). Rebuilt by every
  // candidatesUpToCount: call; invalidated by clearComposition.
  NSMutableArray<NSNumber *> *_candidateIndexMap;
#if GY_HAS_RIME
  RimeApi *_api;
  RimeSessionId _session;
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
  traits.distribution_version = "0.9.15";
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
  const char *keys = code.UTF8String;
  for (const unsigned char *key = (const unsigned char *)keys; key != nullptr && *key != 0; ++key) {
    if (!_api->process_key(_session, *key, 0)) return @[];
  }
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

- (NSArray<NSString *> *)candidatesUpToCount:(NSUInteger)limit {
#if GY_HAS_RIME
  if (![self isReady] || limit == 0) return @[];
  NSMutableArray<NSString *> *result = [NSMutableArray array];
  NSMutableArray<NSNumber *> *indexMap = [NSMutableArray array];
  NSUInteger pagesAdvanced = 0;
  NSUInteger rawIndex = 0;
  while (result.count < limit) {
    RIME_STRUCT(RimeContext, context);
    if (!_api->get_context(_session, &context)) break;
    for (size_t i = 0; i < context.menu.num_candidates && result.count < limit; ++i) {
      const NSUInteger thisRawIndex = rawIndex++;
      const char *text = context.menu.candidates[i].text;
      if (text == nullptr) continue;
      NSString *candidate = [NSString stringWithUTF8String:text];
      if (!GYIsQualityCandidate(candidate)) continue;
      if ([result containsObject:candidate]) continue;
      [result addObject:candidate];
      [indexMap addObject:@(thisRawIndex)];
    }
    const Bool isLastPage = context.menu.is_last_page;
    _api->free_context(&context);
    if (isLastPage) break;
    if (!_api->change_page(_session, False)) break;
    pagesAdvanced++;
  }
  while (pagesAdvanced-- > 0) _api->change_page(_session, True);
  _candidateIndexMap = indexMap;
  return result;
#else
  (void)limit;
  return @[];
#endif
}

- (nullable NSString *)commitCandidateAtAbsoluteIndex:(NSUInteger)index {
#if GY_HAS_RIME
  if (![self isReady]) return nil;
  // Translate the filtered (displayed) index back to the raw Rime index;
  // the quality gate and dedupe may have dropped candidates in between.
  NSUInteger rimeIndex = index;
  if (_candidateIndexMap != nil && index < _candidateIndexMap.count) {
    rimeIndex = _candidateIndexMap[index].unsignedIntegerValue;
  }
  RIME_STRUCT(RimeContext, context);
  if (!_api->get_context(_session, &context)) return nil;
  int pageSize = context.menu.page_size;
  int currentPage = context.menu.page_no;
  _api->free_context(&context);
  if (pageSize <= 0) pageSize = 5;
  const int targetPage = (int)(rimeIndex / (NSUInteger)pageSize);
  const size_t withinPage = rimeIndex % (NSUInteger)pageSize;
  while (currentPage < targetPage) {
    if (!_api->change_page(_session, False)) return nil;
    currentPage++;
  }
  while (currentPage > targetPage) {
    if (!_api->change_page(_session, True)) return nil;
    currentPage--;
  }
  if (!_api->select_candidate_on_current_page(_session, withinPage)) return nil;
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

- (nullable NSString *)remainingCompositionInput {
#if GY_HAS_RIME
  if (![self isReady]) return nil;
  RIME_STRUCT(RimeContext, context);
  if (!_api->get_context(_session, &context)) return nil;
  NSMutableString *rest = nil;
  if (context.composition.preedit != nullptr) {
    rest = [NSMutableString string];
    // Keep only [a-z]; segmentation spaces/apostrophes in the preedit must
    // not leak into the controller's raw composition string.
    for (const char *p = context.composition.preedit; *p != 0; ++p) {
      if (*p >= 'a' && *p <= 'z') [rest appendFormat:@"%c", *p];
    }
  }
  _api->free_context(&context);
  return rest.length != 0 ? rest : nil;
#else
  return nil;
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
  _candidateIndexMap = nil;
#if GY_HAS_RIME
  if ([self isReady]) _api->clear_composition(_session);
#endif
}


- (BOOL)pageUp {
#if GY_HAS_RIME
  return [self isReady] && _api->change_page(_session, True);
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
+ (BOOL)moveLearningDatabaseToTrash:(NSError * _Nullable * _Nullable)error {
  NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                        inDomains:NSUserDomainMask].firstObject;
  NSURL *userDir = [support URLByAppendingPathComponent:@"GYInput/rime" isDirectory:YES];
  NSURL *db = [userDir URLByAppendingPathComponent:@"user.db"];
  if (![NSFileManager.defaultManager fileExistsAtPath:db.path]) {
    return YES; // nothing to delete
  }
  NSURL *trash = [userDir URLByAppendingPathComponent:@"trashed-user.db"];
  [NSFileManager.defaultManager removeItemAtURL:trash error:nil];
  return [NSFileManager.defaultManager moveItemAtURL:db toURL:trash error:error];
}

@end