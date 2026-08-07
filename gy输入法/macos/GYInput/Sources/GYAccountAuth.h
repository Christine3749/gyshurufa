#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main thread whenever `status` or `email` changes.
extern NSString *const GYAccountAuthDidChangeNotification;

typedef NS_ENUM(NSInteger, GYAccountStatus) {
  GYAccountStatusLoggedOut,
  GYAccountStatusLoggingIn,
  GYAccountStatusLoggedIn,
  GYAccountStatusFailed,
};

/// GSYEN account session for Keep sync.
///
/// The refresh token lives in the login Keychain (device-only, unlocked after
/// first unlock); the access token is memory-only and re-derived on demand.
/// The password is never stored, and no token or copied text is ever logged.
@interface GYAccountAuth : NSObject

+ (instancetype)sharedAuth;

@property(nonatomic, readonly) GYAccountStatus status;
/// The signed-in address, or "" when logged out.
@property(nonatomic, readonly, copy) NSString *email;

- (void)loginWithEmail:(NSString *)email
              password:(NSString *)password
            completion:(void (^_Nullable)(BOOL success, NSString *_Nullable message))completion;

/// Yields a valid bearer token, refreshing it first if needed. `nil` means the
/// caller should skip this round: either signed out, or the network failed.
/// The completion runs on the main thread.
- (void)accessTokenWithCompletion:(void (^)(NSString *_Nullable token))completion;

/// Rehydrates `status`/`email` from the Keychain at launch. Cheap and silent.
- (void)restoreSessionIfNeeded;

/// Forgets the session on this Mac. Keep notes are untouched.
- (void)logout;

@end

NS_ASSUME_NONNULL_END
