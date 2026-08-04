#import "GYCandidateQuality.h"

static NSInteger const GYTrustedFrequency = 5000;

static BOOL GYIsHan(unichar c) {
  return (c >= 0x3400 && c <= 0x4DBF) || (c >= 0x4E00 && c <= 0x9FFF) ||
      (c >= 0xF900 && c <= 0xFAFF);
}

static BOOL GYIsCandidate(NSString *text) {
  if (text.length == 0 || text.length > 12) return NO;
  for (NSUInteger i = 0; i < text.length; i++) if (!GYIsHan([text characterAtIndex:i])) return NO;
  return YES;
}

static NSString *GYTraditionalForm(NSString *text) {
  NSStringTransform transform = (NSStringTransform)@"Simplified-Traditional";
  return [text stringByApplyingTransform:transform reverse:NO] ?: text;
}

static NSDictionary<NSString *, NSNumber *> *GYEssayFrequencies(void) {
  static NSDictionary<NSString *, NSNumber *> *frequencies;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSURL *essay = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"Rime/shared/essay.txt"];
    NSString *contents = [NSString stringWithContentsOfURL:essay encoding:NSUTF8StringEncoding error:nil];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [contents enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
      (void)stop; NSRange tab = [line rangeOfString:@"\t"];
      if (tab.location == NSNotFound) return;
      NSInteger score = [[line substringFromIndex:NSMaxRange(tab)] integerValue];
      if (score >= GYTrustedFrequency) result[[line substringToIndex:tab.location]] = @(score);
    }];
    frequencies = [result copy];
  });
  return frequencies;
}

NSString *GYNormalizeCandidate(NSString *text, GYInputMode mode) {
  if (mode == GYInputModeEnglish || text.length == 0) return text;
  NSStringTransform transform = mode == GYInputModeSimplified
      ? (NSStringTransform)@"Traditional-Simplified"
      : (NSStringTransform)@"Simplified-Traditional";
  return [text stringByApplyingTransform:transform reverse:NO] ?: text;
}

BOOL GYCandidateIsTrusted(NSString *text, NSUInteger minimumLength, BOOL isPrimary) {
  if (!GYIsCandidate(text) || text.length < minimumLength) return NO;
  if (isPrimary) return YES;
  NSNumber *score = GYEssayFrequencies()[GYTraditionalForm(text)];
  return score.integerValue >= GYTrustedFrequency;
}
