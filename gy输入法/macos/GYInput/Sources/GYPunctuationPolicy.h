#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Pure port of native/src/PunctuationPolicy.h + KeyPolicy.h's
// ShouldCaptureChinesePunctuation/ChineseCharacter/QuoteCharacter, expressed
// over the literal characters macOS's text input already produced (shift is
// resolved by the OS before -inputText: sees the string), so the mapping is
// exactly Windows' key+shift table without re-deriving virtual key codes.
// Dependency-free so GYInputTests can exercise it directly.
//
// singleQuoteOpen/doubleQuoteOpen persist the smart-quote toggle across calls,
// exactly like Windows' single_quote_open_/double_quote_open_ — never reset
// mid-session, and tracked independently of each other.
NS_INLINE NSString *_Nullable GYChinesePunctuationLookup(NSString *string,
                                                          BOOL *singleQuoteOpen,
                                                          BOOL *doubleQuoteOpen) {
  if ([string isEqualToString:@"'"]) {
    NSString *value = *singleQuoteOpen ? @"‘" : @"’"; // ‘ : ’
    *singleQuoteOpen = !*singleQuoteOpen;
    return value;
  }
  if ([string isEqualToString:@"\""]) {
    NSString *value = *doubleQuoteOpen ? @"“" : @"”"; // “ : ”
    *doubleQuoteOpen = !*doubleQuoteOpen;
    return value;
  }
  static NSDictionary<NSString *, NSString *> *punctuation;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    punctuation = @{
      @",": @"，", @"<": @"《",
      @".": @"。", @">": @"》",
      @";": @"；", @":": @"：",
      @"/": @"、", @"?": @"？",
      @"[": @"【", @"{": @"｛",
      @"]": @"】", @"}": @"｝",
      @"!": @"！",
    };
  });
  return punctuation[string];
}

NS_ASSUME_NONNULL_END
