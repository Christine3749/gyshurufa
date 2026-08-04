#import <Foundation/Foundation.h>

@interface GYLearningStore : NSObject

+ (instancetype)sharedStore;
- (NSArray<NSString *> *)rankedCandidates:(NSArray<NSString *> *)candidates forCode:(NSString *)code;
- (void)recordCandidate:(NSString *)candidate forCode:(NSString *)code;

@end
