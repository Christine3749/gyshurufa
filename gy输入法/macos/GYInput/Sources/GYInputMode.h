#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, GYInputMode) {
  GYInputModeSimplified = 0,
  GYInputModeTraditional = 1,
  GYInputModeEnglish = 2,
};

FOUNDATION_EXPORT NSString *GYInputModeTitle(GYInputMode mode);
FOUNDATION_EXPORT BOOL GYInputModeIsChinese(GYInputMode mode);

/// 输入模式被外部改变（设置面板等）时广播，让每个活着的
/// GYInputController 立刻跟上——引擎模式、模式提示、候选窗一起更新，
/// 而不是等到下一次按键才发现。
///
/// 只写 GYSettingsStore 是不够的：控制器持有自己的 `_mode` 副本，不广播
/// 就会和 store 漂移，之后两边都改不动了。
FOUNDATION_EXPORT NSNotificationName const GYInputModeDidChangeNotification;
