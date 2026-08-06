#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Keeps one isolated Rime session warm while the input method is idle.
/// Client controllers keep their own sessions and never share composition state.
@interface GYRimeRuntime : NSObject

+ (instancetype)sharedRuntime;
- (void)start;

@end

NS_ASSUME_NONNULL_END