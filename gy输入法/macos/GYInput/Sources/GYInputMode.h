#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, GYInputMode) {
  GYInputModeSimplified = 0,
  GYInputModeTraditional = 1,
  GYInputModeEnglish = 2,
};

FOUNDATION_EXPORT NSString *GYInputModeTitle(GYInputMode mode);
FOUNDATION_EXPORT BOOL GYInputModeIsChinese(GYInputMode mode);
