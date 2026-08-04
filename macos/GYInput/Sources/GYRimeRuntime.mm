#import "GYRimeRuntime.h"

static NSURL *GYUserDataDirectory(void) {
  const char *override = getenv("GY_RIME_USER_DATA_DIR");
  if (override && *override) return [NSURL fileURLWithPath:@(override) isDirectory:YES];
  NSString *folder = [NSBundle.mainBundle objectForInfoDictionaryKey:@"GYApplicationSupportFolder"] ?: @"GYInput";
  NSURL *support = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                           inDomains:NSUserDomainMask].firstObject;
  return [[support URLByAppendingPathComponent:folder isDirectory:YES]
      URLByAppendingPathComponent:@"rime" isDirectory:YES];
}

static BOOL GYRefreshGeneratedWorkspace(NSURL *shared, NSURL *user, NSError **error) {
  NSURL *source = [shared URLByAppendingPathComponent:@"build" isDirectory:YES];
  if (![[NSFileManager defaultManager] fileExistsAtPath:source.path]) return YES;
  NSURL *destination = [user URLByAppendingPathComponent:@"build" isDirectory:YES];
  NSFileManager *files = NSFileManager.defaultManager;
  if (![files createDirectoryAtURL:destination withIntermediateDirectories:YES attributes:nil error:error]) return NO;
  for (NSString *name in @[@"default.yaml", @"gy_pinyin.schema.yaml", @"luna_pinyin.prism.bin", @"luna_pinyin.reverse.bin", @"luna_pinyin.table.bin"]) {
    NSURL *from = [source URLByAppendingPathComponent:name]; NSURL *to = [destination URLByAppendingPathComponent:name];
    if (![files fileExistsAtPath:from.path]) { if (error) *error = [NSError errorWithDomain:@"GYInput" code:1 userInfo:nil]; return NO; }
    [files removeItemAtURL:to error:nil];
    if (![files copyItemAtURL:from toURL:to error:error]) return NO;
  }
  return YES;
}

@implementation GYRimeRuntime {
  RimeApi *_api;
  BOOL _ready;
  NSString *_diagnostic;
}

+ (instancetype)sharedRuntime {
  static GYRimeRuntime *runtime;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ runtime = [self new]; });
  return runtime;
}

- (instancetype)init {
  self = [super init];
  if (self) [self start];
  return self;
}

- (void)start {
  NSURL *resources = NSBundle.mainBundle.resourceURL;
  NSURL *shared = [resources URLByAppendingPathComponent:@"Rime/shared" isDirectory:YES];
  if (![[NSFileManager defaultManager] fileExistsAtPath:shared.path]) {
    _diagnostic = @"bundled Rime data is missing";
    return;
  }
  NSURL *user = GYUserDataDirectory();
  NSError *error;
  if (![[NSFileManager defaultManager] createDirectoryAtURL:user withIntermediateDirectories:YES attributes:nil error:&error]) {
    _diagnostic = error.localizedDescription ?: @"cannot create local Rime data";
    return;
  }
  if (!GYRefreshGeneratedWorkspace(shared, user, &error)) {
    _diagnostic = error.localizedDescription ?: @"cannot refresh generated Rime data";
    return;
  }
  _api = rime_get_api();
  if (!_api) { _diagnostic = @"rime_get_api returned null"; return; }
  NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"dev";
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = shared.path.UTF8String;
  traits.user_data_dir = user.path.UTF8String;
  traits.distribution_name = "GY Input Method";
  traits.distribution_code_name = "gyinput";
  traits.distribution_version = version.UTF8String;
  traits.app_name = "rime.gyinput";
  traits.min_log_level = 2;
  _api->setup(&traits);
  _api->initialize(&traits);
  if (_api->start_maintenance(False)) _api->join_maintenance_thread();
  _ready = YES;
  _diagnostic = @"ready";
}

- (RimeApi *)api { return _api; }
- (BOOL)ready { return _ready; }
- (NSString *)diagnostic { return _diagnostic; }

@end
