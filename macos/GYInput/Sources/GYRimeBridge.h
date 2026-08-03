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
- (NSUInteger)currentPageNumber;
- (BOOL)canPageUp;
- (BOOL)canPageDown;
- (nullable NSString *)commitCandidateAtIndex:(NSUInteger)index;
- (BOOL)pageUp;
- (BOOL)pageDown;
- (void)clearComposition;

/// Moves only Rime's per-user learning database to the Trash. Bundled schemas
/// and GY custom phrases live elsewhere and are deliberately preserved. The
/// current IME process keeps its open database handles until it is restarted.
+ (BOOL)moveLearningDatabaseToTrash:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
