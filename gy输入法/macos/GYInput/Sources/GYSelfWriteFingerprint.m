#import "GYSelfWriteFingerprint.h"

BOOL GYIsOwnPasteboardWrite(NSString *selfWrittenFingerprint,
                            NSInteger selfWrittenChangeCount,
                            NSString *observedFingerprint,
                            NSInteger observedChangeCount) {
  if (selfWrittenFingerprint == nil) return NO;
  if (observedChangeCount != selfWrittenChangeCount) return NO;
  if (![observedFingerprint isKindOfClass:NSString.class]) return NO;
  return [observedFingerprint isEqualToString:selfWrittenFingerprint];
}
