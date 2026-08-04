#import "GYInputMode.h"

NSString *GYInputModeTitle(GYInputMode mode) {
  switch (mode) {
    // This compact title is used by the input-source menu and status line.
    // Keep it exactly aligned with the candidate badge and Windows contract:
    // 简 / 繁 / EN. The Settings window may use the longer descriptive names.
    case GYInputModeSimplified: return @"简";
    case GYInputModeTraditional: return @"繁";
    case GYInputModeEnglish: return @"EN";
  }
}

BOOL GYInputModeIsChinese(GYInputMode mode) {
  return mode == GYInputModeSimplified || mode == GYInputModeTraditional;
}
