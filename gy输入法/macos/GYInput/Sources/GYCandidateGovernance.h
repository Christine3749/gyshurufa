#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A visible candidate and the backend that owns its eventual commit.
@interface GYCandidateSelection : NSObject
@property(nonatomic, copy, readonly) NSString *text;
@property(nonatomic, readonly, getter=isLocalPhrase) BOOL localPhrase;
/// YES for a candidate sourced from a shortened pinyin fallback query (spec
/// §5.2 "gei → ge"), not the composition the user actually typed. Its
/// rimeDisplayIndex belongs to a DIFFERENT Rime session state than the one
/// active at commit time — it must be committed as plain text (like
/// localPhrase), never via GYRimeBridge -commitCandidateAtAbsoluteIndex:.
@property(nonatomic, readonly, getter=isDirectFallback) BOOL directFallback;
@property(nonatomic, readonly) NSUInteger rimeDisplayIndex;
@end

/// Applies the shared Windows/Mac ordering policy without losing Rime indices.
@interface GYCandidateGovernance : NSObject
/// `exactCount`: how many of the leading entries in `rimeCandidates` came
/// from the exact composition (see GYRimeBridge
/// -candidatesForCode:upToCount:exactCount:) — anything at or beyond that
/// index is marked directFallback. Pass rimeCandidates.count when there is
/// no fallback distinction to make (e.g. a plain, unbroadened candidate
/// list) so every entry is treated as exact.
+ (NSArray<GYCandidateSelection *> *)selectionsForRimeCandidates:(NSArray<NSString *> *)rimeCandidates
                                                    customPhrases:(NSArray<NSString *> *)customPhrases
                                                       exactCount:(NSUInteger)exactCount;
@end

NS_ASSUME_NONNULL_END
