#import "GYPreferencesController.h"
#import "GYInputMode.h"
#import "GYRimeBridge.h"
#import "GYSettingsStore.h"
#import "GYUpdateService.h"

static NSColor *GYSettingsColor(CGFloat red, CGFloat green, CGFloat blue) {
  return [NSColor colorWithSRGBRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:1.0];
}

static BOOL GYUsesReleaseUpdateChannel(void) {
  NSString *channel = [NSBundle.mainBundle objectForInfoDictionaryKey:@"GYUpdateChannel"];
  return [channel isEqualToString:@"release"];
}
static NSColor *GYSettingsInk(void) { return GYSettingsColor(17, 19, 24); }
static NSColor *GYSettingsSurface(void) { return GYSettingsColor(25, 28, 35); }
static NSColor *GYSettingsBorder(void) { return GYSettingsColor(49, 53, 61); }
static NSColor *GYSettingsText(void) { return GYSettingsColor(246, 248, 252); }
static NSColor *GYSettingsMuted(void) { return GYSettingsColor(151, 157, 169); }
static NSColor *GYSettingsBlue(void) { return GYSettingsColor(40, 99, 235); }

@interface GYSettingsPanel : NSPanel
@end

@implementation GYSettingsPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end

@interface GYSettingsBackgroundView : NSView
@end

@implementation GYSettingsBackgroundView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  [GYSettingsInk() setFill];
  [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:14.0 yRadius:14.0] fill];
  [GYSettingsBorder() setStroke];
  [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:14.0 yRadius:14.0] stroke];

  NSDictionary *wordmark = @{
    NSFontAttributeName: [NSFont systemFontOfSize:24.0 weight:NSFontWeightHeavy],
    NSForegroundColorAttributeName: NSColor.whiteColor,
  };
  [@"GY" drawInRect:NSMakeRect(24, 22, 54, 31) withAttributes:wordmark];
  [@"输入法设置" drawInRect:NSMakeRect(90, 21, 220, 27) withAttributes:@{
    NSFontAttributeName: [NSFont systemFontOfSize:17.0 weight:NSFontWeightSemibold],
    NSForegroundColorAttributeName: GYSettingsText(),
  }];
  [@"所有内容仅保存在本机" drawInRect:NSMakeRect(90, 50, 240, 18) withAttributes:@{
    NSFontAttributeName: [NSFont systemFontOfSize:10.0 weight:NSFontWeightRegular],
    NSForegroundColorAttributeName: GYSettingsMuted(),
  }];
  [@"输入语言" drawInRect:NSMakeRect(24, 166, 200, 18) withAttributes:@{
    NSFontAttributeName: [NSFont systemFontOfSize:10.0 weight:NSFontWeightRegular],
    NSForegroundColorAttributeName: GYSettingsMuted(),
  }];
  [@"候选窗样式" drawInRect:NSMakeRect(24, 244, 200, 18) withAttributes:@{
    NSFontAttributeName: [NSFont systemFontOfSize:10.0 weight:NSFontWeightRegular],
    NSForegroundColorAttributeName: GYSettingsMuted(),
  }];
  [@"候选字体" drawInRect:NSMakeRect(24, 322, 200, 18) withAttributes:@{
    NSFontAttributeName: [NSFont systemFontOfSize:10.0 weight:NSFontWeightRegular],
    NSForegroundColorAttributeName: GYSettingsMuted(),
  }];
  [@"本地短语与词库" drawInRect:NSMakeRect(24, 400, 200, 18) withAttributes:@{
    NSFontAttributeName: [NSFont systemFontOfSize:10.0 weight:NSFontWeightRegular],
    NSForegroundColorAttributeName: GYSettingsMuted(),
  }];
}
@end

@interface GYAboutBackgroundView : NSView
@end

@implementation GYAboutBackgroundView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  [GYSettingsInk() setFill];
  [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:14.0 yRadius:14.0] fill];
  [GYSettingsBorder() setStroke];
  [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:14.0 yRadius:14.0] stroke];
}
@end

@interface GYSettingsButton : NSButton
@property(nonatomic) BOOL gySelected;
@property(nonatomic) BOOL gyPrimary;
@end

@implementation GYSettingsButton
- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    self.bordered = NO;
    self.wantsLayer = YES;
    self.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold];
  }
  return self;
}
- (void)setGySelected:(BOOL)gySelected { _gySelected = gySelected; [self setNeedsDisplay:YES]; }
- (void)setGyPrimary:(BOOL)gyPrimary { _gyPrimary = gyPrimary; [self setNeedsDisplay:YES]; }
- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSColor *fill = (self.gySelected || self.gyPrimary) ? GYSettingsBlue() : GYSettingsSurface();
  NSColor *stroke = (self.gySelected || self.gyPrimary) ? GYSettingsBlue() : GYSettingsBorder();
  [fill setFill];
  [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:8.0 yRadius:8.0] fill];
  [stroke setStroke];
  [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:8.0 yRadius:8.0] stroke];
  NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
  style.alignment = NSTextAlignmentCenter;
  style.lineBreakMode = NSLineBreakByTruncatingTail;
  [self.title drawInRect:NSInsetRect(self.bounds, 4.0, 8.0) withAttributes:@{
    NSFontAttributeName: self.font,
    NSForegroundColorAttributeName: GYSettingsText(),
    NSParagraphStyleAttributeName: style,
  }];
}
@end

@interface GYPreferencesController ()
@property(nonatomic, strong) GYSettingsPanel *window;
@property(nonatomic, strong) GYSettingsButton *simplifiedButton;
@property(nonatomic, strong) GYSettingsButton *traditionalButton;
@property(nonatomic, strong) GYSettingsButton *englishButton;
@property(nonatomic, strong) GYSettingsButton *blueNightThemeButton;
@property(nonatomic, strong) GYSettingsButton *warmWhiteThemeButton;
@property(nonatomic, strong) GYSettingsButton *graphiteThemeButton;
@property(nonatomic, strong) GYSettingsButton *compactFontButton;
@property(nonatomic, strong) GYSettingsButton *standardFontButton;
@property(nonatomic, strong) GYSettingsButton *largeFontButton;
@property(nonatomic, strong) NSTextField *codeField;
@property(nonatomic, strong) NSTextField *phraseField;
@property(nonatomic, strong) NSTextField *phraseSummary;
@property(nonatomic, strong) GYSettingsPanel *aboutWindow;
@property(nonatomic, strong) NSButton *automaticUpdateCheckBox;
@property(nonatomic, strong) NSTextField *aboutUpdateStatus;
@end

@implementation GYPreferencesController

+ (instancetype)sharedController {
  static GYPreferencesController *controller;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ controller = [[self alloc] init]; });
  return controller;
}

- (GYSettingsButton *)buttonWithTitle:(NSString *)title frame:(NSRect)frame action:(SEL)action {
  GYSettingsButton *button = [[GYSettingsButton alloc] initWithFrame:frame];
  button.title = title;
  button.target = self;
  button.action = action;
  return button;
}

- (NSTextField *)fieldWithFrame:(NSRect)frame placeholder:(NSString *)placeholder {
  NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
  field.placeholderString = placeholder;
  field.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
  field.textColor = GYSettingsText();
  field.backgroundColor = GYSettingsSurface();
  field.drawsBackground = YES;
  field.bordered = YES;
  field.bezelStyle = NSTextFieldRoundedBezel;
  field.focusRingType = NSFocusRingTypeNone;
  return field;
}

- (NSTextField *)labelWithString:(NSString *)text frame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color alignment:(NSTextAlignment)alignment {
  NSTextField *label = [NSTextField labelWithString:text];
  label.frame = frame;
  label.font = font;
  label.textColor = color;
  label.alignment = alignment;
  label.lineBreakMode = NSLineBreakByTruncatingTail;
  return label;
}

- (void)ensureWindow {
  if (self.window != nil) return;
  NSRect frame = NSMakeRect(0, 0, 520, 564);
  self.window = [[GYSettingsPanel alloc] initWithContentRect:frame
                                                    styleMask:NSWindowStyleMaskBorderless
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
  self.window.title = @"GY 输入法设置";
  self.window.opaque = NO;
  self.window.backgroundColor = NSColor.clearColor;
  self.window.hasShadow = YES;
  self.window.movableByWindowBackground = YES;
  self.window.level = NSFloatingWindowLevel;
  self.window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
  self.window.animationBehavior = NSWindowAnimationBehaviorNone;

  GYSettingsBackgroundView *content = [[GYSettingsBackgroundView alloc] initWithFrame:frame];
  self.window.contentView = content;

  GYSettingsButton *close = [self buttonWithTitle:@"×" frame:NSMakeRect(475, 19, 24, 26) action:@selector(close:)];
  close.font = [NSFont systemFontOfSize:18.0 weight:NSFontWeightRegular];
  close.gyPrimary = NO;
  [content addSubview:close];

  NSView *localData = [[NSView alloc] initWithFrame:NSMakeRect(24, 90, 472, 54)];
  localData.wantsLayer = YES;
  localData.layer.backgroundColor = GYSettingsSurface().CGColor;
  localData.layer.cornerRadius = 9.0;
  localData.layer.borderWidth = 1.0;
  localData.layer.borderColor = GYSettingsBorder().CGColor;
  NSTextField *localDataTitle = [NSTextField labelWithString:@"本地词库与学习"];
  localDataTitle.frame = NSMakeRect(15, 26, 120, 18);
  localDataTitle.textColor = GYSettingsText();
  localDataTitle.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold];
  NSTextField *localDataDetail = [NSTextField labelWithString:@"内置词库、短语与学习记录只保存在此 Mac"];
  localDataDetail.frame = NSMakeRect(15, 8, 300, 16);
  localDataDetail.textColor = GYSettingsMuted();
  localDataDetail.font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightRegular];
  GYSettingsButton *resetLearning = [self buttonWithTitle:@"清除学习" frame:NSMakeRect(360, 12, 96, 30) action:@selector(resetLearning:)];
  [localData addSubview:localDataTitle];
  [localData addSubview:localDataDetail];
  [localData addSubview:resetLearning];
  [content addSubview:localData];

  self.simplifiedButton = [self buttonWithTitle:@"简体" frame:NSMakeRect(24, 192, 150, 34) action:@selector(selectMode:)];
  self.simplifiedButton.tag = GYInputModeSimplified;
  self.traditionalButton = [self buttonWithTitle:@"繁体" frame:NSMakeRect(185, 192, 150, 34) action:@selector(selectMode:)];
  self.traditionalButton.tag = GYInputModeTraditional;
  self.englishButton = [self buttonWithTitle:@"EN" frame:NSMakeRect(346, 192, 150, 34) action:@selector(selectMode:)];
  self.englishButton.tag = GYInputModeEnglish;
  [content addSubview:self.simplifiedButton];
  [content addSubview:self.traditionalButton];
  [content addSubview:self.englishButton];

  self.blueNightThemeButton = [self buttonWithTitle:@"GY 蓝夜" frame:NSMakeRect(24, 270, 150, 34) action:@selector(selectTheme:)];
  self.blueNightThemeButton.tag = 0;
  self.warmWhiteThemeButton = [self buttonWithTitle:@"暖白" frame:NSMakeRect(185, 270, 150, 34) action:@selector(selectTheme:)];
  self.warmWhiteThemeButton.tag = 1;
  self.graphiteThemeButton = [self buttonWithTitle:@"石墨" frame:NSMakeRect(346, 270, 150, 34) action:@selector(selectTheme:)];
  self.graphiteThemeButton.tag = 2;
  [content addSubview:self.blueNightThemeButton];
  [content addSubview:self.warmWhiteThemeButton];
  [content addSubview:self.graphiteThemeButton];

  self.compactFontButton = [self buttonWithTitle:@"紧凑 15" frame:NSMakeRect(24, 348, 150, 34) action:@selector(selectCandidateFont:)];
  self.compactFontButton.tag = 15;
  self.standardFontButton = [self buttonWithTitle:@"标准 16" frame:NSMakeRect(185, 348, 150, 34) action:@selector(selectCandidateFont:)];
  self.standardFontButton.tag = 16;
  self.largeFontButton = [self buttonWithTitle:@"大号 17" frame:NSMakeRect(346, 348, 150, 34) action:@selector(selectCandidateFont:)];
  self.largeFontButton.tag = 17;
  [content addSubview:self.compactFontButton];
  [content addSubview:self.standardFontButton];
  [content addSubview:self.largeFontButton];

  NSView *phrases = [[NSView alloc] initWithFrame:NSMakeRect(24, 426, 472, 82)];
  phrases.wantsLayer = YES;
  phrases.layer.backgroundColor = GYSettingsSurface().CGColor;
  phrases.layer.cornerRadius = 9.0;
  phrases.layer.borderWidth = 1.0;
  phrases.layer.borderColor = GYSettingsBorder().CGColor;
  self.codeField = [self fieldWithFrame:NSMakeRect(12, 39, 124, 30) placeholder:@"编码，如 dz"];
  self.phraseField = [self fieldWithFrame:NSMakeRect(145, 39, 315, 30) placeholder:@"词条，如 地址 | 我的电子邮箱"];
  self.phraseSummary = [NSTextField labelWithString:@""];
  self.phraseSummary.frame = NSMakeRect(13, 12, 448, 17);
  self.phraseSummary.textColor = GYSettingsMuted();
  self.phraseSummary.font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightRegular];
  self.phraseSummary.lineBreakMode = NSLineBreakByTruncatingTail;
  [phrases addSubview:self.codeField];
  [phrases addSubview:self.phraseField];
  [phrases addSubview:self.phraseSummary];
  [content addSubview:phrases];

  GYSettingsButton *clear = [self buttonWithTitle:@"清空短语" frame:NSMakeRect(24, 524, 96, 28) action:@selector(clearPhrases:)];
  GYSettingsButton *export = [self buttonWithTitle:@"导出设置" frame:NSMakeRect(130, 524, 96, 28) action:@selector(exportSettings:)];
  GYSettingsButton *import = [self buttonWithTitle:@"导入设置" frame:NSMakeRect(236, 524, 96, 28) action:@selector(importSettings:)];
  GYSettingsButton *save = [self buttonWithTitle:@"保存词条" frame:NSMakeRect(342, 524, 154, 28) action:@selector(savePhrase:)];
  save.gyPrimary = YES;
  [content addSubview:clear];
  [content addSubview:export];
  [content addSubview:import];
  [content addSubview:save];
}

- (void)reload {
  GYSettingsStore *store = GYSettingsStore.sharedStore;
  self.simplifiedButton.gySelected = store.inputMode == GYInputModeSimplified;
  self.traditionalButton.gySelected = store.inputMode == GYInputModeTraditional;
  self.englishButton.gySelected = store.inputMode == GYInputModeEnglish;
  self.blueNightThemeButton.gySelected = store.candidateTheme == 0;
  self.warmWhiteThemeButton.gySelected = store.candidateTheme == 1;
  self.graphiteThemeButton.gySelected = store.candidateTheme == 2;
  self.compactFontButton.gySelected = store.candidateFontSize == 15;
  self.standardFontButton.gySelected = store.candidateFontSize == 16;
  self.largeFontButton.gySelected = store.candidateFontSize == 17;
  NSDictionary<NSString *, NSArray<NSString *> *> *phrases = store.customPhrases;
  if (phrases.count == 0) {
    self.phraseSummary.stringValue = @"尚无本地词条。一个编码可用 | 保存多个短语。";
  } else {
    NSArray<NSString *> *codes = [[phrases.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] subarrayWithRange:NSMakeRange(0, MIN(3, phrases.count))];
    NSMutableArray<NSString *> *samples = [NSMutableArray array];
    NSUInteger entryCount = 0;
    for (NSArray<NSString *> *entries in phrases.allValues) entryCount += entries.count;
    for (NSString *code in codes) [samples addObject:[NSString stringWithFormat:@"%@=%@", code, [phrases[code] componentsJoinedByString:@" | "]]];
    self.phraseSummary.stringValue = [NSString stringWithFormat:@"已保存 %lu 个编码、%lu 条词条：%@", (unsigned long)phrases.count, (unsigned long)entryCount, [samples componentsJoinedByString:@"  ·  "]];
  }
}

- (void)show {
  [self ensureWindow];
  [self reload];
  [self.window center];
  [NSApp activateIgnoringOtherApps:YES];
  [self.window makeKeyAndOrderFront:nil];
}

- (void)ensureAboutWindow {
  if (self.aboutWindow != nil) return;
  NSRect frame = NSMakeRect(0, 0, 460, 456);
  self.aboutWindow = [[GYSettingsPanel alloc] initWithContentRect:frame
                                                         styleMask:NSWindowStyleMaskBorderless
                                                           backing:NSBackingStoreBuffered
                                                             defer:NO];
  self.aboutWindow.title = @"关于 GY 输入法";
  self.aboutWindow.opaque = NO;
  self.aboutWindow.backgroundColor = NSColor.clearColor;
  self.aboutWindow.hasShadow = YES;
  self.aboutWindow.movableByWindowBackground = YES;
  self.aboutWindow.level = NSFloatingWindowLevel;
  self.aboutWindow.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
  self.aboutWindow.animationBehavior = NSWindowAnimationBehaviorNone;

  GYAboutBackgroundView *content = [[GYAboutBackgroundView alloc] initWithFrame:frame];
  self.aboutWindow.contentView = content;
  GYSettingsButton *close = [self buttonWithTitle:@"×" frame:NSMakeRect(414, 17, 24, 26) action:@selector(closeAbout:)];
  close.font = [NSFont systemFontOfSize:18.0 weight:NSFontWeightRegular];
  [content addSubview:close];

  NSURL *iconURL = [NSBundle.mainBundle URLForResource:@"GYInputMenuIcon" withExtension:@"png"];
  NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(164, 42, 132, 132)];
  icon.image = iconURL == nil ? nil : [[NSImage alloc] initWithContentsOfURL:iconURL];
  icon.imageScaling = NSImageScaleProportionallyUpOrDown;
  [content addSubview:icon];

  NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"开发版";
  NSString *build = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"—";
  [content addSubview:[self labelWithString:@"GY 输入法" frame:NSMakeRect(30, 191, 400, 34)
                                      font:[NSFont systemFontOfSize:25.0 weight:NSFontWeightBold]
                                     color:GYSettingsText() alignment:NSTextAlignmentCenter]];
  [content addSubview:[self labelWithString:[NSString stringWithFormat:@"%@（%@）", version, build]
                                       frame:NSMakeRect(30, 232, 400, 21)
                                        font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular]
                                       color:GYSettingsMuted() alignment:NSTextAlignmentCenter]];
  [content addSubview:[self labelWithString:@"离线拼音 · 本地学习 · 简 / 繁 / EN"
                                       frame:NSMakeRect(30, 276, 400, 19)
                                        font:[NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular]
                                       color:GYSettingsText() alignment:NSTextAlignmentCenter]];

  self.automaticUpdateCheckBox = [NSButton checkboxWithTitle:@"有新版本时自动检查更新" target:self action:@selector(toggleAutomaticUpdateChecks:)];
  self.automaticUpdateCheckBox.frame = NSMakeRect(130, 319, 220, 24);
  self.automaticUpdateCheckBox.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
  self.automaticUpdateCheckBox.contentTintColor = GYSettingsBlue();
  [content addSubview:self.automaticUpdateCheckBox];
  self.aboutUpdateStatus = [self labelWithString:@""
                                             frame:NSMakeRect(34, 351, 392, 20)
                                              font:[NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular]
                                             color:GYSettingsMuted() alignment:NSTextAlignmentCenter];
  [content addSubview:self.aboutUpdateStatus];
  GYSettingsButton *feedback = [self buttonWithTitle:@"反馈" frame:NSMakeRect(70, 394, 100, 31) action:@selector(sendFeedback:)];
  GYSettingsButton *check = [self buttonWithTitle:@"检查更新" frame:NSMakeRect(180, 394, 120, 31) action:@selector(checkForUpdates:)];
  check.gyPrimary = YES;
  GYSettingsButton *done = [self buttonWithTitle:@"完成" frame:NSMakeRect(310, 394, 80, 31) action:@selector(closeAbout:)];
  [content addSubview:feedback];
  [content addSubview:done];
  [content addSubview:check];
}

- (void)showAbout {
  [self ensureAboutWindow];
  self.automaticUpdateCheckBox.state = GYSettingsStore.sharedStore.automaticUpdateChecks ? NSControlStateValueOn : NSControlStateValueOff;
  self.aboutUpdateStatus.stringValue = GYUsesReleaseUpdateChannel()
      ? @"更新只从 shurufa.wang 的正式发布源获取。"
      : @"内测更新只从 shurufa.wang 的内测发布源获取。";
  [self.aboutWindow center];
  [NSApp activateIgnoringOtherApps:YES];
  [self.aboutWindow makeKeyAndOrderFront:nil];
}

- (void)closeAbout:(id)sender { (void)sender; [self.aboutWindow orderOut:nil]; }

- (void)sendFeedback:(id)sender {
  (void)sender;
  NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"开发版";
  NSString *build = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"—";
  NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
  NSString *subject = @"GY 输入法 macOS 反馈";
  NSString *body = [NSString stringWithFormat:
      @"请描述问题的复现步骤（不要包含密码、原始输入内容或个人词库）：\\n\\n"
       "使用的 App：\\n"
       "复现步骤：\\n"
       "实际结果：\\n"
       "期望结果：\\n\\n"
       "--- 自动附带的环境信息 ---\\n"
       "GY 输入法：%@（%@）\\n"
       "macOS：%ld.%ld.%ld\\n"
       "更新通道：%@\\n",
      version, build, (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion,
      GYUsesReleaseUpdateChannel() ? @"正式" : @"内测"];
  NSURLComponents *components = [[NSURLComponents alloc] init];
  components.scheme = @"mailto";
  components.path = @"contact@gsyen.com";
  components.queryItems = @[
    [NSURLQueryItem queryItemWithName:@"subject" value:subject],
    [NSURLQueryItem queryItemWithName:@"body" value:body],
  ];
  NSURL *URL = components.URL;
  if (URL != nil && [NSWorkspace.sharedWorkspace openURL:URL]) return;
  self.aboutUpdateStatus.stringValue = @"无法打开邮件应用：contact@gsyen.com";
}

- (void)toggleAutomaticUpdateChecks:(NSButton *)sender {
  GYSettingsStore.sharedStore.automaticUpdateChecks = sender.state == NSControlStateValueOn;
  self.aboutUpdateStatus.stringValue = sender.state == NSControlStateValueOn ? @"已开启自动检查更新。" : @"已关闭自动检查更新。";
}

- (void)checkForUpdates:(id)sender {
  (void)sender;
  self.aboutUpdateStatus.stringValue = @"正在检查更新…";
  __weak typeof(self) weakSelf = self;
  [GYUpdateService.sharedService checkForUpdatesWithCompletion:^(NSString *status, NSURL *packageURL) {
    GYPreferencesController *strongSelf = weakSelf;
    if (strongSelf == nil) return;
    strongSelf.aboutUpdateStatus.stringValue = status;
    if (packageURL == nil) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"发现 GY 输入法新版本";
    alert.informativeText = @"下载更新包后，macOS 会要求管理员授权，以安全替换系统输入法。";
    [alert addButtonWithTitle:@"前往下载"];
    [alert addButtonWithTitle:@"稍后"];
    [alert beginSheetModalForWindow:strongSelf.aboutWindow completionHandler:^(NSModalResponse response) {
      if (response == NSAlertFirstButtonReturn) [NSWorkspace.sharedWorkspace openURL:packageURL];
    }];
  }];
}

- (void)close:(id)sender { (void)sender; [self.window orderOut:nil]; }

- (void)selectMode:(GYSettingsButton *)sender {
  GYSettingsStore.sharedStore.inputMode = (GYInputMode)sender.tag;
  [self reload];
}

- (void)selectTheme:(GYSettingsButton *)sender {
  GYSettingsStore.sharedStore.candidateTheme = sender.tag;
  [self reload];
}

- (void)selectCandidateFont:(GYSettingsButton *)sender {
  GYSettingsStore.sharedStore.candidateFontSize = sender.tag;
  [self reload];
}

- (void)resetLearning:(id)sender {
  (void)sender;
  NSAlert *confirmation = [[NSAlert alloc] init];
  confirmation.messageText = @"清除本地学习记录？";
  confirmation.informativeText = @"Rime 学习数据库会移到废纸篓。内置词库和 GY 本地短语不会被删除；重新登录后才会完全生效。";
  [confirmation addButtonWithTitle:@"移到废纸篓"];
  [confirmation addButtonWithTitle:@"取消"];
  __weak typeof(self) weakSelf = self;
  [confirmation beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
    if (response != NSAlertFirstButtonReturn) return;
    NSError *error = nil;
    if ([GYRimeBridge moveLearningDatabaseToTrash:&error]) {
      NSAlert *success = [[NSAlert alloc] init];
      success.messageText = @"学习记录已移到废纸篓";
      success.informativeText = @"请先切换到其他输入法，再注销并重新登录，以安全启用新的本地学习数据库。";
      [success addButtonWithTitle:@"好"];
      [success beginSheetModalForWindow:weakSelf.window completionHandler:nil];
      return;
    }
    NSAlert *failure = [[NSAlert alloc] init];
    failure.messageText = @"无法清除学习记录";
    failure.informativeText = error.localizedDescription ?: @"请在关闭所有 GY 输入法会话后重试。";
    [failure addButtonWithTitle:@"好"];
    [failure beginSheetModalForWindow:weakSelf.window completionHandler:nil];
  }];
}

- (void)showSettingsAlertWithTitle:(NSString *)title message:(NSString *)message {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = title;
  alert.informativeText = message;
  [alert addButtonWithTitle:@"好"];
  [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)exportSettings:(id)sender {
  (void)sender;
  NSSavePanel *panel = [NSSavePanel savePanel];
  panel.title = @"导出 GY 输入法设置";
  panel.nameFieldStringValue = @"GYInput-settings.json";
  panel.allowedFileTypes = @[@"json"];
  panel.canCreateDirectories = YES;
  __weak typeof(self) weakSelf = self;
  [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
    if (response != NSModalResponseOK || panel.URL == nil) return;
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:GYSettingsStore.sharedStore.portableSettingsBackup
                                                    options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                      error:&error];
    if (data == nil || ![data writeToURL:panel.URL options:NSDataWritingAtomic error:&error]) {
      [weakSelf showSettingsAlertWithTitle:@"无法导出设置" message:error.localizedDescription ?: @"请检查保存位置后重试。"];
      return;
    }
    [weakSelf showSettingsAlertWithTitle:@"已导出设置" message:@"已保存输入模式、候选窗样式、字体、更新偏好和本地短语词库。学习记录与输入内容不会导出。"];
  }];
}

- (void)importSettings:(id)sender {
  (void)sender;
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  panel.title = @"导入 GY 输入法设置";
  panel.allowedFileTypes = @[@"json"];
  panel.allowsMultipleSelection = NO;
  panel.canChooseDirectories = NO;
  panel.canChooseFiles = YES;
  __weak typeof(self) weakSelf = self;
  [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
    if (response != NSModalResponseOK || panel.URL == nil) return;
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:panel.URL options:0 error:&error];
    if (data == nil || data.length > 256 * 1024) {
      [weakSelf showSettingsAlertWithTitle:@"无法导入设置" message:data == nil ? (error.localizedDescription ?: @"无法读取设置文件。") : @"设置备份超过 256 KB，未导入任何内容。"];
      return;
    }
    id decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![decoded isKindOfClass:NSDictionary.class] ||
        ![GYSettingsStore.sharedStore importPortableSettingsBackup:decoded error:&error]) {
      [weakSelf showSettingsAlertWithTitle:@"无法导入设置" message:error.localizedDescription ?: @"这不是有效的 GY 输入法设置备份。"];
      return;
    }
    [weakSelf reload];
    [weakSelf showSettingsAlertWithTitle:@"已导入设置" message:@"本地短语词库、输入模式和候选窗外观已更新。请在当前输入完成后，再切换或按 Shift 使用新模式。"];
  }];
}

- (void)savePhrase:(id)sender {
  (void)sender;
  NSString *code = self.codeField.stringValue.lowercaseString;
  NSString *phraseText = self.phraseField.stringValue;
  if (code.length == 0 || phraseText.length == 0) { NSBeep(); return; }
  NSMutableArray<NSString *> *phrases = [NSMutableArray array];
  for (NSString *part in [phraseText componentsSeparatedByString:@"|"]) {
    NSString *phrase = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (phrase.length != 0) [phrases addObject:phrase];
  }
  if (phrases.count == 0) { NSBeep(); return; }
  [GYSettingsStore.sharedStore setCustomPhrases:phrases forCode:code];
  self.codeField.stringValue = @"";
  self.phraseField.stringValue = @"";
  [self reload];
}

- (void)clearPhrases:(id)sender {
  (void)sender;
  [GYSettingsStore.sharedStore clearCustomPhrases];
  [self reload];
}

@end
