#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A visible candidate and the backend that owns its eventual commit.
@interface GYCandidateSelection : NSObject
@property(nonatomic, copy, readonly) NSString *text;
@property(nonatomic, readonly, getter=isLocalPhrase) BOOL localPhrase;
@property(nonatomic, readonly) NSUInteger rimeDisplayIndex;
@end

/// Applies the shared Windows/Mac ordering policy without losing Rime indices.
@interface GYCandidateGovernance : NSObject
+ (NSArray<GYCandidateSelection *> *)selectionsForRimeCandidates:(NSArray<NSString *> *)rimeCandidates
                                                    customPhrases:(NSArray<NSString *> *)customPhrases;
@end

NS_ASSUME_NONNULL_END
