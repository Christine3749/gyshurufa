#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^GYUpdateCheckCompletion)(NSString *status, NSURL * _Nullable packageURL);

/// Checks only the official GY release feed. Installation stays user-approved:
/// replacing an input method in /Library/Input Methods requires macOS
/// administrator authorization and a notarized Developer ID package.
@interface GYUpdateService : NSObject

+ (instancetype)sharedService;
- (void)checkForUpdatesIfNeeded;
- (void)checkForUpdatesWithCompletion:(nullable GYUpdateCheckCompletion)completion;

@end

NS_ASSUME_NONNULL_END
