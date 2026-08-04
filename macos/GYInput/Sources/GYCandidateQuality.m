#import "GYCandidateQuality.h"

NSString *GYNormalizeCandidate(NSString *text, GYInputMode mode) {
  if (mode == GYInputModeEnglish || text.length == 0) return text;
  NSStringTransform transform = mode == GYInputModeSimplified
      ? (NSStringTransform)@"Traditional-Simplified"
      : (NSStringTransform)@"Simplified-Traditional";
  return [text stringByApplyingTransform:transform reverse:NO] ?: text;
}
