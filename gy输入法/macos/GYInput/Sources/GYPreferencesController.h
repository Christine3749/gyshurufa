#import <AppKit/AppKit.h>

@interface GYPreferencesController : NSObject
+ (instancetype)sharedController;
- (void)show;
- (void)showAbout;
/// 直接打开到剪贴板页，供系统输入菜单的「剪贴板」使用。
- (void)showClipboardPage;
@end
