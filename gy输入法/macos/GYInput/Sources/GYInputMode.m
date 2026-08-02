#import "GYInputMode.h"

NSString *GYInputModeTitle(GYInputMode mode) {
  switch (mode) {
    case GYInputModeSimplified: return @"简体";
    case GYInputModeTraditional: return @"繁體";
    case GYInputModeEnglish: return @"EN";
  }
}

BOOL GYInputModeIsChinese(GYInputMode mode) {
  return mode == GYInputModeSimplified || mode == GYInputModeTraditional;
}
