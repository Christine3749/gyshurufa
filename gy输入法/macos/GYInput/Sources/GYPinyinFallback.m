#import "GYPinyinFallback.h"

NSString *_Nullable GYNextFallbackPinyinCode(NSString *code) {
  NSString *fallback = code.lowercaseString;
  if (fallback.length <= 2) return nil;
  fallback = [fallback substringToIndex:fallback.length - 1];
  while (fallback.length > 0 && [fallback hasSuffix:@"'"]) {
    fallback = [fallback substringToIndex:fallback.length - 1];
  }
  return fallback.length < 2 ? nil : fallback;
}
