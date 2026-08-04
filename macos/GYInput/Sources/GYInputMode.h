#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, GYInputMode) {
  GYInputModeSimplified = 0,
  GYInputModeTraditional = 1,
  GYInputModeEnglish = 2,
};

FOUNDATION_EXPORT NSString *GYInputModeLabel(GYInputMode mode);
FOUNDATION_EXPORT BOOL GYInputModeUsesChinese(GYInputMode mode);

@interface GYInputModeStore : NSObject

@property(nonatomic, readonly) GYInputMode mode;

+ (instancetype)sharedStore;
- (GYInputMode)cycleMode;
- (void)setMode:(GYInputMode)mode;

@end
