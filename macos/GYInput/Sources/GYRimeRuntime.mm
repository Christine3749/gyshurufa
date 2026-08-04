#import "GYRimeRuntime.h"

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
  NSURL *support = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                           inDomains:NSUserDomainMask].firstObject;
  NSURL *user = [[support URLByAppendingPathComponent:@"GYInput" isDirectory:YES]
      URLByAppendingPathComponent:@"rime" isDirectory:YES];
  NSError *error;
  if (![[NSFileManager defaultManager] createDirectoryAtURL:user withIntermediateDirectories:YES attributes:nil error:&error]) {
    _diagnostic = error.localizedDescription ?: @"cannot create local Rime data";
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
