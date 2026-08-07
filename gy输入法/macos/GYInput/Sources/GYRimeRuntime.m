#import "GYRimeRuntime.h"

#import "GYInputMode.h"
#import "GYRimeBridge.h"
#import "GYSettingsStore.h"

@interface GYRimeRuntime ()
@property(nonatomic, strong) GYRimeBridge *warmBridge;
@end

@implementation GYRimeRuntime

+ (instancetype)sharedRuntime {
  static GYRimeRuntime *runtime;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ runtime = [[self alloc] initPrivate]; });
  return runtime;
}

- (instancetype)init { return [GYRimeRuntime sharedRuntime]; }

- (instancetype)initPrivate {
  self = [super init];
  return self;
}

- (void)start {
  [NSNotificationCenter.defaultCenter addObserver:self
                                         selector:@selector(warmStartSettingDidChange:)
                                             name:GYSettingsStoreWarmStartDidChangeNotification
                                           object:GYSettingsStore.sharedStore];
  [self refreshWarmSession];
}

- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)warmStartSettingDidChange:(NSNotification *)note {
  (void)note;
  if (!NSThread.isMainThread) {
    dispatch_async(dispatch_get_main_queue(), ^{ [self refreshWarmSession]; });
    return;
  }
  [self refreshWarmSession];
}

- (void)refreshWarmSession {
  if (!GYSettingsStore.sharedStore.warmStartEnabled) {
    self.warmBridge = nil;
    return;
  }
  if (self.warmBridge.isReady) return;

  NSURL *shared = [NSBundle.mainBundle URLForResource:@"rime-data" withExtension:nil];
  NSURL *support = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                          inDomains:NSUserDomainMask] firstObject];
  NSURL *user = [[support URLByAppendingPathComponent:@"GYInput" isDirectory:YES]
                       URLByAppendingPathComponent:@"rime" isDirectory:YES];
  [NSFileManager.defaultManager createDirectoryAtURL:user withIntermediateDirectories:YES attributes:nil error:nil];
  self.warmBridge = [[GYRimeBridge alloc] initWithSharedDataURL:shared userDataURL:user];
}

@end