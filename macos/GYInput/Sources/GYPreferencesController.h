#import <AppKit/AppKit.h>

@interface GYPreferencesController : NSObject
+ (instancetype)sharedController;
- (void)show;
- (void)showAbout;
@end
