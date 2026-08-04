#import "GYInputMode.h"

static NSString *const GYInputModeKey = @"GYInputMode";

NSString *GYInputModeLabel(GYInputMode mode) {
  switch (mode) {
    case GYInputModeTraditional: return @"繁";
    case GYInputModeEnglish: return @"EN";
    default: return @"简";
  }
}

BOOL GYInputModeUsesChinese(GYInputMode mode) {
  return mode == GYInputModeSimplified || mode == GYInputModeTraditional;
}

@implementation GYInputModeStore {
  GYInputMode _mode;
}

+ (instancetype)sharedStore {
  static GYInputModeStore *store;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ store = [self new]; });
  return store;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    NSInteger stored = [[NSUserDefaults standardUserDefaults] integerForKey:GYInputModeKey];
    _mode = stored >= GYInputModeSimplified && stored <= GYInputModeEnglish
        ? (GYInputMode)stored : GYInputModeSimplified;
  }
  return self;
}

- (GYInputMode)mode {
  @synchronized (self) { return _mode; }
}

- (GYInputMode)cycleMode {
  @synchronized (self) {
    [self setMode:(GYInputMode)((_mode + 1) % 3)];
    return _mode;
  }
}

- (void)setMode:(GYInputMode)mode {
  if (mode < GYInputModeSimplified || mode > GYInputModeEnglish) return;
  @synchronized (self) {
    _mode = mode;
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:GYInputModeKey];
  }
}

@end
