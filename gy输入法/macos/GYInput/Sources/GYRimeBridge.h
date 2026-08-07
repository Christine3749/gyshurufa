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
// Collects up to `limit` candidates by walking Rime pages forward, then
// restores the original page so commit math stays relative to page zero.
- (NSArray<NSString *> *)candidatesUpToCount:(NSUInteger)limit;
- (nullable NSString *)commitCandidateAtIndex:(NSUInteger)index;
// Commits a candidate by absolute index within a candidatesUpToCount: window
// (pages the Rime session to the right page, then selects on that page).
- (nullable NSString *)commitCandidateAtAbsoluteIndex:(NSUInteger)index;
// Raw pinyin Rime still holds after a partial commit; nil when fully consumed.
- (nullable NSString *)remainingCompositionInput;
- (void)clearComposition;

// Class method to move the learning database to trash.
+ (BOOL)moveLearningDatabaseToTrash:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END