#import "GYSettingsStore.h"

static NSString *const kMode = @"inputMode";
static NSString *const kLastChineseMode = @"lastChineseMode";
static NSString *const kCandidateTheme = @"candidateTheme";
static NSString *const kCandidateFontSize = @"candidateFontSize";
static NSString *const kAutomaticUpdateChecks = @"automaticUpdateChecks";
static NSString *const kLastUpdateCheckTimestamp = @"lastUpdateCheckTimestamp";
static NSString *const kCustomPhrases = @"customPhrases";
static NSString *const kBackupFormat = @"gyinput-macos-settings";
static NSInteger const kBackupVersion = 1;
static NSString *const kBackupErrorDomain = @"wang.shurufa.GYInput.Settings";

static NSError *GYSettingsBackupError(NSString *description) {
  return [NSError errorWithDomain:kBackupErrorDomain code:1
                         userInfo:@{NSLocalizedDescriptionKey: description}];
}

static BOOL GYBackupInteger(NSDictionary<NSString *, id> *backup, NSString *key, NSInteger minimum, NSInteger maximum, NSInteger *result) {
  id value = backup[key];
  if (![value isKindOfClass:NSNumber.class]) return NO;
  NSInteger integer = [value integerValue];
  if (integer < minimum || integer > maximum) return NO;
  if (result != NULL) *result = integer;
  return YES;
}

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
  if (_document[kCandidateTheme] == nil) _document[kCandidateTheme] = @0;
  if (_document[kCandidateFontSize] == nil) _document[kCandidateFontSize] = @16;
  if (_document[kAutomaticUpdateChecks] == nil) _document[kAutomaticUpdateChecks] = @YES;
  if (_document[kLastUpdateCheckTimestamp] == nil) _document[kLastUpdateCheckTimestamp] = @0;
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
- (NSInteger)candidateTheme { return MAX(0, MIN(2, [_document[kCandidateTheme] integerValue])); }
- (void)setCandidateTheme:(NSInteger)value { _document[kCandidateTheme] = @(MAX(0, MIN(2, value))); [self save]; }
- (NSInteger)candidateFontSize { return MAX(15, MIN(17, [_document[kCandidateFontSize] integerValue])); }
- (void)setCandidateFontSize:(NSInteger)value { _document[kCandidateFontSize] = @(MAX(15, MIN(17, value))); [self save]; }
- (BOOL)automaticUpdateChecks { return [_document[kAutomaticUpdateChecks] boolValue]; }
- (void)setAutomaticUpdateChecks:(BOOL)value { _document[kAutomaticUpdateChecks] = @(value); [self save]; }
- (NSTimeInterval)lastUpdateCheckTimestamp { return MAX(0, [_document[kLastUpdateCheckTimestamp] doubleValue]); }
- (void)setLastUpdateCheckTimestamp:(NSTimeInterval)value { _document[kLastUpdateCheckTimestamp] = @(MAX(0, value)); [self save]; }
- (NSDictionary<NSString *,NSString *> *)customPhrases { return [_document[kCustomPhrases] copy]; }
- (void)setCustomPhrase:(NSString *)phrase forCode:(NSString *)code {
  if (code.length == 0 || phrase.length == 0) return;
  NSMutableDictionary *phrases = [_document[kCustomPhrases] mutableCopy];
  phrases[code.lowercaseString] = phrase;
  _document[kCustomPhrases] = phrases;
  [self save];
}
- (void)clearCustomPhrases {
  _document[kCustomPhrases] = @{};
  [self save];
}
- (NSArray<NSString *> *)candidatesByAddingCustomPhrases:(NSArray<NSString *> *)rimeCandidates forCode:(NSString *)code {
  NSString *phrase = self.customPhrases[code.lowercaseString];
  if (phrase.length == 0) return rimeCandidates;
  NSMutableOrderedSet *result = [NSMutableOrderedSet orderedSetWithObject:phrase];
  [result addObjectsFromArray:rimeCandidates];
  return result.array;
}

- (NSDictionary<NSString *,id> *)portableSettingsBackup {
  return @{
    @"format": kBackupFormat,
    @"version": @(kBackupVersion),
    kMode: @(self.inputMode),
    kLastChineseMode: @(self.lastChineseMode),
    kCandidateTheme: @(self.candidateTheme),
    kCandidateFontSize: @(self.candidateFontSize),
    kAutomaticUpdateChecks: @(self.automaticUpdateChecks),
    kCustomPhrases: self.customPhrases,
  };
}

- (BOOL)importPortableSettingsBackup:(NSDictionary<NSString *,id> *)backup
                                error:(NSError * _Nullable * _Nullable)error {
  if (![backup[@"format"] isKindOfClass:NSString.class] ||
      ![backup[@"format"] isEqualToString:kBackupFormat] ||
      ![backup[@"version"] isKindOfClass:NSNumber.class] ||
      [backup[@"version"] integerValue] != kBackupVersion) {
    if (error != NULL) *error = GYSettingsBackupError(@"这不是有效的 GY 输入法设置备份。");
    return NO;
  }
  NSInteger mode = 0, lastChineseMode = 0, theme = 0, fontSize = 0;
  if (!GYBackupInteger(backup, kMode, GYInputModeSimplified, GYInputModeEnglish, &mode) ||
      !GYBackupInteger(backup, kLastChineseMode, GYInputModeSimplified, GYInputModeTraditional, &lastChineseMode) ||
      !GYBackupInteger(backup, kCandidateTheme, 0, 2, &theme) ||
      !GYBackupInteger(backup, kCandidateFontSize, 15, 17, &fontSize) ||
      ![backup[kAutomaticUpdateChecks] isKindOfClass:NSNumber.class] ||
      ![backup[kCustomPhrases] isKindOfClass:NSDictionary.class]) {
    if (error != NULL) *error = GYSettingsBackupError(@"备份中的设置格式不正确。");
    return NO;
  }
  NSDictionary *incomingPhrases = backup[kCustomPhrases];
  if (incomingPhrases.count > 512) {
    if (error != NULL) *error = GYSettingsBackupError(@"备份中的本地短语过多。");
    return NO;
  }
  NSMutableDictionary<NSString *, NSString *> *phrases = [NSMutableDictionary dictionaryWithCapacity:incomingPhrases.count];
  for (id key in incomingPhrases) {
    id value = incomingPhrases[key];
    if (![key isKindOfClass:NSString.class] || ![value isKindOfClass:NSString.class]) {
      if (error != NULL) *error = GYSettingsBackupError(@"备份中的本地短语格式不正确。");
      return NO;
    }
    NSString *code = [(NSString *)key lowercaseString];
    NSString *phrase = (NSString *)value;
    if (code.length == 0 || code.length > 64 || phrase.length == 0 || phrase.length > 512) {
      if (error != NULL) *error = GYSettingsBackupError(@"备份中的本地短语长度无效。");
      return NO;
    }
    phrases[code] = phrase;
  }
  _document[kMode] = @(mode);
  _document[kLastChineseMode] = @(lastChineseMode);
  _document[kCandidateTheme] = @(theme);
  _document[kCandidateFontSize] = @(fontSize);
  _document[kAutomaticUpdateChecks] = @([backup[kAutomaticUpdateChecks] boolValue]);
  _document[kCustomPhrases] = phrases;
  [self save];
  return YES;
}
@end
