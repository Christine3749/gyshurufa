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

@implementation GYRimeBridge {
  NSURL *_sharedDataURL;
  NSURL *_userDataURL;
  NSString *_diagnostic;
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
@end