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
/// Applies the same bundled OpenCC tables as the active Rime schema so a
/// local phrase follows 简 / 繁 mode instead of bypassing conversion.
- (NSString *)localCandidateForPhrase:(NSString *)phrase inputMode:(GYInputMode)mode;
- (NSUInteger)currentPageNumber;
- (BOOL)canPageUp;
- (BOOL)canPageDown;
- (nullable NSString *)commitCandidateAtIndex:(NSUInteger)index;
/// Selects a candidate from a previously displayed physical Rime page.  The
/// controller uses this for its virtual 5 × 5 stream, where local phrases can
/// precede a Rime page without changing Rime's own candidate indices.
- (nullable NSString *)commitCandidateAtPage:(NSUInteger)pageNumber index:(NSUInteger)index;
- (BOOL)pageUp;
- (BOOL)pageDown;
- (void)clearComposition;

/// Moves only Rime's per-user learning database to the Trash. Bundled schemas
/// and GY custom phrases live elsewhere and are deliberately preserved. The
/// current IME process keeps its open database handles until it is restarted.
+ (BOOL)moveLearningDatabaseToTrash:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
