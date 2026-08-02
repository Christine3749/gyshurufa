#import "GYSettingsStore.h"

static NSString *const kMode = @"inputMode";
static NSString *const kLastChineseMode = @"lastChineseMode";
static NSString *const kCandidatePageSize = @"candidatePageSize";
static NSString *const kShowExpandedCandidates = @"showExpandedCandidates";
static NSString *const kCustomPhrases = @"customPhrases";

@implementation GYSettingsStore {
  NSMutableDictionary *_document;
  NSURL *_url;
}

+ (instancetype)sharedStore {
  static GYSettingsStore *store;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ store = [[self alloc] initPrivate]; });
  return store;
}

- (instancetype)init { return [GYSettingsStore sharedStore]; }

- (instancetype)initPrivate {
  self = [super init];
  if (!self) return nil;
  NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                        inDomains:NSUserDomainMask].firstObject;
  NSURL *directory = [support URLByAppendingPathComponent:@"GYInput" isDirectory:YES];
  [NSFileManager.defaultManager createDirectoryAtURL:directory
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:nil];
  _url = [directory URLByAppendingPathComponent:@"settings.json"];
  NSData *data = [NSData dataWithContentsOfURL:_url];
  NSDictionary *saved = data == nil ? nil : [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  _document = [saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
  if (_document[kMode] == nil) _document[kMode] = @(GYInputModeSimplified);
  if (_document[kLastChineseMode] == nil) _document[kLastChineseMode] = @(GYInputModeSimplified);
  if (_document[kCandidatePageSize] == nil) _document[kCandidatePageSize] = @5;
  if (_document[kShowExpandedCandidates] == nil) _document[kShowExpandedCandidates] = @NO;
  if (![_document[kCustomPhrases] isKindOfClass:NSDictionary.class]) _document[kCustomPhrases] = @{};
  return self;
}

- (void)save {
  NSData *data = [NSJSONSerialization dataWithJSONObject:_document options:NSJSONWritingPrettyPrinted error:nil];
  if (data != nil) [data writeToURL:_url options:NSDataWritingAtomic error:nil];
}

- (GYInputMode)inputMode { return [_document[kMode] integerValue]; }
- (void)setInputMode:(GYInputMode)mode {
  if (mode < GYInputModeSimplified || mode > GYInputModeEnglish) mode = GYInputModeSimplified;
  _document[kMode] = @(mode);
  if (GYInputModeIsChinese(mode)) _document[kLastChineseMode] = @(mode);
  [self save];
}
- (GYInputMode)lastChineseMode { return [_document[kLastChineseMode] integerValue]; }
- (void)setLastChineseMode:(GYInputMode)mode {
  _document[kLastChineseMode] = @(mode == GYInputModeTraditional ? mode : GYInputModeSimplified);
  [self save];
}
- (NSInteger)candidatePageSize { return MAX(5, MIN(9, [_document[kCandidatePageSize] integerValue])); }
- (void)setCandidatePageSize:(NSInteger)value { _document[kCandidatePageSize] = @(MAX(5, MIN(9, value))); [self save]; }
- (BOOL)showExpandedCandidates { return [_document[kShowExpandedCandidates] boolValue]; }
- (void)setShowExpandedCandidates:(BOOL)value { _document[kShowExpandedCandidates] = @(value); [self save]; }
- (NSDictionary<NSString *,NSString *> *)customPhrases { return [_document[kCustomPhrases] copy]; }
- (void)setCustomPhrase:(NSString *)phrase forCode:(NSString *)code {
  if (code.length == 0 || phrase.length == 0) return;
  NSMutableDictionary *phrases = [_document[kCustomPhrases] mutableCopy];
  phrases[code.lowercaseString] = phrase;
  _document[kCustomPhrases] = phrases;
  [self save];
}
- (NSArray<NSString *> *)candidatesByAddingCustomPhrases:(NSArray<NSString *> *)rimeCandidates forCode:(NSString *)code {
  NSString *phrase = self.customPhrases[code.lowercaseString];
  if (phrase.length == 0) return rimeCandidates;
  NSMutableOrderedSet *result = [NSMutableOrderedSet orderedSetWithObject:phrase];
  [result addObjectsFromArray:rimeCandidates];
  return result.array;
}
@end
