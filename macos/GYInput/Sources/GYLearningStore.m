#import "GYLearningStore.h"

static NSString *const GYLearningKey = @"GYInputLocalLearning";

@implementation GYLearningStore

+ (instancetype)sharedStore {
  static GYLearningStore *store;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ store = [self new]; });
  return store;
}

- (NSString *)keyForCode:(NSString *)code candidate:(NSString *)candidate {
  return [NSString stringWithFormat:@"%@\x1f%@", code, candidate];
}

- (NSDictionary<NSString *, NSNumber *> *)scores {
  NSDictionary *stored = [[NSUserDefaults standardUserDefaults] dictionaryForKey:GYLearningKey];
  return [stored isKindOfClass:NSDictionary.class] ? stored : @{};
}

- (NSArray<NSString *> *)rankedCandidates:(NSArray<NSString *> *)candidates forCode:(NSString *)code {
  NSDictionary *scores = self.scores;
  return [candidates sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
    NSInteger leftScore = [scores[[self keyForCode:code candidate:left]] integerValue];
    NSInteger rightScore = [scores[[self keyForCode:code candidate:right]] integerValue];
    if (leftScore == rightScore) return [candidates indexOfObject:left] < [candidates indexOfObject:right]
        ? NSOrderedAscending : NSOrderedDescending;
    return leftScore > rightScore ? NSOrderedAscending : NSOrderedDescending;
  }];
}

- (void)recordCandidate:(NSString *)candidate forCode:(NSString *)code {
  if (code.length == 0 || candidate.length == 0) return;
  @synchronized (self) {
    NSMutableDictionary *scores = [self.scores mutableCopy];
    NSString *key = [self keyForCode:code candidate:candidate];
    NSInteger next = MIN(100000, [scores[key] integerValue] + 1);
    scores[key] = @(next);
    [[NSUserDefaults standardUserDefaults] setObject:scores forKey:GYLearningKey];
  }
}

@end
