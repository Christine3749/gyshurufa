#import <Foundation/Foundation.h>
#import "GYInputMode.h"

NS_ASSUME_NONNULL_BEGIN

// This is the only macOS target API allowed to call librime. The controller
// never reads a Rime context directly, which keeps platform code small.
@interface GYRimeBridge : NSObject

- (instancetype)initWithSharedDataURL:(NSURL *)sharedDataURL
                           userDataURL:(NSURL *)userDataURL;
- (BOOL)isReady;
- (NSString *)diagnostic;
- (void)setInputMode:(GYInputMode)mode;
- (NSArray<NSString *> *)candidatesForCode:(NSString *)code;
- (NSArray<NSString *> *)currentCandidates;
- (nullable NSString *)commitCandidateAtIndex:(NSUInteger)index;
- (BOOL)pageUp;
- (BOOL)pageDown;
- (void)clearComposition;

@end

NS_ASSUME_NONNULL_END