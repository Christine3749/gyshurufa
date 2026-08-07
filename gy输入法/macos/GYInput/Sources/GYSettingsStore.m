#import "GYSettingsStore.h"

NSNotificationName const GYSettingsStoreWarmStartDidChangeNotification = @"GYSettingsStoreWarmStartDidChangeNotification";

static NSString *const kMode = @"inputMode";
static NSString *const kLastChineseMode = @"lastChineseMode";
static NSString *const kCandidateTheme = @"candidateTheme";
static NSString *const kCandidateFontSize = @"candidateFontSize";
static NSString *const kAutomaticUpdateChecks = @"automaticUpdateChecks";
static NSString *const kWarmStartEnabled = @"warmStartEnabled";
static NSString *const kClipboardSyncEnabled = @"clipboardSyncEnabled";
static NSString *const kClipboardInstantPaste = @"clipboardInstantPaste";
static NSString *const kLastUpdateCheckTimestamp = @"lastUpdateCheckTimestamp";
static NSString *const kCustomPhrases = @"customPhrases";
static NSString *const kAccountName = @"accountName";
static NSString *const kBackupFormat = @"gyinput-macos-settings";
static NSInteger const kBackupVersion = 2;
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

// Keep local phrases entirely in settings.json, but use the same `code=a|b`
// model as the Windows build: every code can surface several phrases in a
// stable, user-defined order. Version 1 backups stored one string per code;
// accepting that shape here makes the migration lossless.
static NSDictionary<NSString *, NSArray<NSString *> *> *GYValidatedCustomPhrases(id value,
                                                                                   NSString **message) {
  if (![value isKindOfClass:NSDictionary.class]) {
    if (message != NULL) *message = @"本地短语格式不正确。";
    return nil;
  }
  NSDictionary *incoming = value;
  if (incoming.count > 512) {
    if (message != NULL) *message = @"本地短语编码过多。";
    return nil;
  }
  NSMutableDictionary<NSString *, NSArray<NSString *> *> *result = [NSMutableDictionary dictionaryWithCapacity:incoming.count];
  NSUInteger totalPhraseCount = 0;
  for (id key in incoming) {
    id rawPhrases = incoming[key];
    if (![key isKindOfClass:NSString.class]) {
      if (message != NULL) *message = @"本地短语编码格式不正确。";
      return nil;
    }
    NSString *code = [(NSString *)key lowercaseString];
    if (code.length == 0 || code.length > 64) {
      if (message != NULL) *message = @"本地短语编码长度无效。";
      return nil;
    }
    NSArray *rawList = [rawPhrases isKindOfClass:NSString.class] ? @[rawPhrases] : rawPhrases;
    if (![rawList isKindOfClass:NSArray.class] || rawList.count == 0 || rawList.count > 64) {
      if (message != NULL) *message = @"本地短语内容格式不正确。";
      return nil;
    }
    NSMutableOrderedSet<NSString *> *phrases = [NSMutableOrderedSet orderedSetWithCapacity:rawList.count];
    for (id rawPhrase in rawList) {
      if (![rawPhrase isKindOfClass:NSString.class]) {
        if (message != NULL) *message = @"本地短语内容格式不正确。";
        return nil;
      }
      NSString *phrase = [(NSString *)rawPhrase stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if (phrase.length == 0 || phrase.length > 512) {
        if (message != NULL) *message = @"本地短语长度无效。";
        return nil;
      }
      [phrases addObject:phrase];
    }
    totalPhraseCount += phrases.count;
    if (totalPhraseCount > 2048) {
      if (message != NULL) *message = @"本地词条过多。";
      return nil;
    }
    result[code] = phrases.array;
  }
  return result;
}

static NSInteger GYNormalizedCandidateFontSize(NSInteger value) {
  if (value <= 13) return 13;
  if (value >= 17) return 17;
  return 15;
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
  // Contract: 13|15|17 (紧凑|默认|大). The retired 16 ("标准") folds to 15.
  if (_document[kCandidateFontSize] == nil || [_document[kCandidateFontSize] integerValue] == 16) {
    _document[kCandidateFontSize] = @15;
  }
  if (_document[kAccountName] == nil) _document[kAccountName] = @"";
  if (_document[kAutomaticUpdateChecks] == nil) _document[kAutomaticUpdateChecks] = @YES;
  if (_document[kWarmStartEnabled] == nil) _document[kWarmStartEnabled] = @YES;
  if (_document[kClipboardSyncEnabled] == nil) _document[kClipboardSyncEnabled] = @YES;
  if (_document[kClipboardInstantPaste] == nil) _document[kClipboardInstantPaste] = @YES;
  if (_document[kLastUpdateCheckTimestamp] == nil) _document[kLastUpdateCheckTimestamp] = @0;
  NSString *phraseMigrationError = nil;
  NSDictionary<NSString *, NSArray<NSString *> *> *phrases = GYValidatedCustomPhrases(_document[kCustomPhrases], &phraseMigrationError);
  _document[kCustomPhrases] = phrases ?: @{};
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
- (NSInteger)candidateFontSize { return GYNormalizedCandidateFontSize([_document[kCandidateFontSize] integerValue]); }
- (void)setCandidateFontSize:(NSInteger)value { _document[kCandidateFontSize] = @(GYNormalizedCandidateFontSize(value)); [self save]; }
- (NSString *)accountName {
  id value = _document[kAccountName];
  return [value isKindOfClass:NSString.class] ? value : @"";
}
- (void)setAccountName:(NSString *)value {
  NSString *trimmed = [(value ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (trimmed.length > 256) trimmed = [trimmed substringToIndex:256];
  _document[kAccountName] = trimmed;
  [self save];
}
- (BOOL)automaticUpdateChecks { return [_document[kAutomaticUpdateChecks] boolValue]; }
- (void)setAutomaticUpdateChecks:(BOOL)value { _document[kAutomaticUpdateChecks] = @(value); [self save]; }
- (BOOL)warmStartEnabled { return [_document[kWarmStartEnabled] boolValue]; }
- (void)setWarmStartEnabled:(BOOL)value {
  value = !!value;
  if (self.warmStartEnabled == value) return;
  _document[kWarmStartEnabled] = @(value);
  [self save];
  [NSNotificationCenter.defaultCenter postNotificationName:GYSettingsStoreWarmStartDidChangeNotification object:self];
}
- (BOOL)clipboardSyncEnabled { return [_document[kClipboardSyncEnabled] boolValue]; }
- (void)setClipboardSyncEnabled:(BOOL)value { _document[kClipboardSyncEnabled] = @(value); [self save]; }
- (BOOL)clipboardInstantPaste { return [_document[kClipboardInstantPaste] boolValue]; }
- (void)setClipboardInstantPaste:(BOOL)value { _document[kClipboardInstantPaste] = @(value); [self save]; }
- (NSTimeInterval)lastUpdateCheckTimestamp { return MAX(0, [_document[kLastUpdateCheckTimestamp] doubleValue]); }
- (void)setLastUpdateCheckTimestamp:(NSTimeInterval)value { _document[kLastUpdateCheckTimestamp] = @(MAX(0, value)); [self save]; }
- (NSDictionary<NSString *,NSArray<NSString *> *> *)customPhrases { return [_document[kCustomPhrases] copy]; }
- (NSArray<NSString *> *)candidatesByAddingCustomPhrases:(NSArray<NSString *> *)candidates forCode:(NSString *)code {
  NSArray<NSString *> *custom = self.customPhrases[code.lowercaseString];
  if (custom.count == 0) return candidates;
  NSMutableArray<NSString *> *result = [NSMutableArray arrayWithArray:custom];
  for (NSString *candidate in candidates) {
    if (![custom containsObject:candidate]) {
      [result addObject:candidate];
    }
  }
  return result;
}

- (NSArray<NSString *> *)customPhrasesForCode:(NSString *)code {
  id phrases = self.customPhrases[code.lowercaseString];
  return [phrases isKindOfClass:NSArray.class] ? phrases : @[];
}
- (void)setCustomPhrase:(NSString *)phrase forCode:(NSString *)code {
  [self setCustomPhrases:(phrase.length == 0 ? @[] : @[phrase]) forCode:code];
}
- (void)setCustomPhrases:(NSArray<NSString *> *)phrases forCode:(NSString *)code {
  NSString *normalizedCode = code.lowercaseString;
  if (normalizedCode.length == 0 || normalizedCode.length > 64) return;
  NSMutableOrderedSet<NSString *> *normalizedPhrases = [NSMutableOrderedSet orderedSet];
  for (id rawPhrase in phrases) {
    if (![rawPhrase isKindOfClass:NSString.class]) continue;
    NSString *phrase = [(NSString *)rawPhrase stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (phrase.length != 0 && phrase.length <= 512) [normalizedPhrases addObject:phrase];
    if (normalizedPhrases.count == 64) break;
  }
  NSMutableDictionary *documentPhrases = [_document[kCustomPhrases] mutableCopy];
  if (normalizedPhrases.count == 0) [documentPhrases removeObjectForKey:normalizedCode];
  else documentPhrases[normalizedCode] = normalizedPhrases.array;
  _document[kCustomPhrases] = [documentPhrases copy];
  [self save];
}
- (void)clearCustomPhrases {
  _document[kCustomPhrases] = @{};
  [self save];
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
    kWarmStartEnabled: @(self.warmStartEnabled),
    kClipboardSyncEnabled: @(self.clipboardSyncEnabled),
    kClipboardInstantPaste: @(self.clipboardInstantPaste),
    kCustomPhrases: self.customPhrases,
  };
}

- (BOOL)importPortableSettingsBackup:(NSDictionary<NSString *,id> *)backup
                                error:(NSError * _Nullable * _Nullable)error {
  if (![backup[@"format"] isKindOfClass:NSString.class] ||
      ![backup[@"format"] isEqualToString:kBackupFormat] ||
      ![backup[@"version"] isKindOfClass:NSNumber.class] ||
      [backup[@"version"] integerValue] < 1 ||
      [backup[@"version"] integerValue] > kBackupVersion) {
    if (error != NULL) *error = GYSettingsBackupError(@"这不是有效的 GY 输入法设置备份。");
    return NO;
  }
  const NSInteger version = [backup[@"version"] integerValue];
  NSInteger mode = 0, lastChineseMode = 0, theme = 0, fontSize = 0;
  if (!GYBackupInteger(backup, kMode, GYInputModeSimplified, GYInputModeEnglish, &mode) ||
      !GYBackupInteger(backup, kLastChineseMode, GYInputModeSimplified, GYInputModeTraditional, &lastChineseMode) ||
      !GYBackupInteger(backup, kCandidateTheme, 0, 2, &theme) ||
      !GYBackupInteger(backup, kCandidateFontSize, 13, 17, &fontSize) ||
      ![backup[kAutomaticUpdateChecks] isKindOfClass:NSNumber.class] ||
      (version >= 2 &&
       (![backup[kWarmStartEnabled] isKindOfClass:NSNumber.class] ||
        ![backup[kClipboardSyncEnabled] isKindOfClass:NSNumber.class] ||
        ![backup[kClipboardInstantPaste] isKindOfClass:NSNumber.class]))) {
    if (error != NULL) *error = GYSettingsBackupError(@"备份中的设置格式不正确。");
    return NO;
  }
  NSString *phraseError = nil;
  NSDictionary<NSString *, NSArray<NSString *> *> *phrases = GYValidatedCustomPhrases(backup[kCustomPhrases], &phraseError);
  if (phrases == nil) {
    if (error != NULL) *error = GYSettingsBackupError(phraseError ?: @"备份中的本地短语格式不正确。");
    return NO;
  }
  _document[kMode] = @(mode);
  _document[kLastChineseMode] = @(lastChineseMode);
  _document[kCandidateTheme] = @(theme);
  _document[kCandidateFontSize] = @(GYNormalizedCandidateFontSize(fontSize));
  _document[kAutomaticUpdateChecks] = @([backup[kAutomaticUpdateChecks] boolValue]);
  _document[kWarmStartEnabled] = version >= 2 ? @([backup[kWarmStartEnabled] boolValue]) : @YES;
  _document[kClipboardSyncEnabled] = version >= 2 ? @([backup[kClipboardSyncEnabled] boolValue]) : @YES;
  _document[kClipboardInstantPaste] = version >= 2 ? @([backup[kClipboardInstantPaste] boolValue]) : @YES;
  _document[kCustomPhrases] = phrases;
  [self save];
  [NSNotificationCenter.defaultCenter postNotificationName:GYSettingsStoreWarmStartDidChangeNotification object:self];
  return YES;
}
@end




