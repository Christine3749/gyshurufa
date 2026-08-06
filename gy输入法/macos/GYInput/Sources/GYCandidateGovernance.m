#import "GYCandidateGovernance.h"

@interface GYCandidateSelection ()
- (instancetype)initWithText:(NSString *)text localPhrase:(BOOL)localPhrase rimeDisplayIndex:(NSUInteger)rimeDisplayIndex;
@end

@implementation GYCandidateSelection
- (instancetype)initWithText:(NSString *)text localPhrase:(BOOL)localPhrase rimeDisplayIndex:(NSUInteger)rimeDisplayIndex {
  self = [super init];
  if (self) {
    _text = [text copy];
    _localPhrase = localPhrase;
    _rimeDisplayIndex = rimeDisplayIndex;
  }
  return self;
}
@end

@implementation GYCandidateGovernance
+ (NSArray<GYCandidateSelection *> *)selectionsForRimeCandidates:(NSArray<NSString *> *)rimeCandidates customPhrases:(NSArray<NSString *> *)customPhrases {
  NSMutableSet<NSString *> *rimeTexts = [NSMutableSet set];
  for (id candidate in rimeCandidates) {
    if ([candidate isKindOfClass:NSString.class] && ((NSString *)candidate).length != 0) [rimeTexts addObject:candidate];
  }
  NSMutableSet<NSString *> *seen = [NSMutableSet set];
  NSMutableArray<GYCandidateSelection *> *result = [NSMutableArray array];
  for (id phrase in customPhrases) {
    if (![phrase isKindOfClass:NSString.class] || ((NSString *)phrase).length == 0 || [rimeTexts containsObject:phrase] || [seen containsObject:phrase]) continue;
    [seen addObject:phrase];
    [result addObject:[[GYCandidateSelection alloc] initWithText:phrase localPhrase:YES rimeDisplayIndex:NSNotFound]];
  }
  NSUInteger rimeDisplayIndex = 0;
  for (id candidate in rimeCandidates) {
    if (![candidate isKindOfClass:NSString.class] || ((NSString *)candidate).length == 0) {
      rimeDisplayIndex += 1;
      continue;
    }
    if (![seen containsObject:candidate]) {
      [seen addObject:candidate];
      [result addObject:[[GYCandidateSelection alloc] initWithText:candidate localPhrase:NO rimeDisplayIndex:rimeDisplayIndex]];
    }
    rimeDisplayIndex += 1;
  }
  return result.copy;
}
@end
