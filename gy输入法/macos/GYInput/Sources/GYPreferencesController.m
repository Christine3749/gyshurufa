#import "GYPreferencesController.h"
#import "GYSettingsStore.h"
#import "GYRimeBridge.h"
#import "GYInputMode.h"
#import "GYClipboardHistory.h"
#import "GYAccountAuth.h"
#import "GYKeepSync.h"

// SETTINGS-PANEL-DESIGN.md: fixed 520×680, four pages, palette follows the
// candidate theme, only 完成 persists (× discards with a confirmation).

static const CGFloat kWindowW = 520;
static const CGFloat kWindowH = 680;

@interface GYPalette : NSObject
@property(nonatomic, strong) NSColor *ink, *surface, *surfaceAlt, *surfaceHover, *border, *text, *muted, *accent, *onAccent;
+ (instancetype)forTheme:(NSInteger)theme;
@end

@implementation GYPalette
+ (instancetype)forTheme:(NSInteger)theme {
  GYPalette *p = [[GYPalette alloc] init];
  NSColor *(^rgb)(NSUInteger, NSUInteger, NSUInteger) = ^NSColor *(NSUInteger r, NSUInteger g, NSUInteger b) {
    return [NSColor colorWithSRGBRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1];
  };
  // surfaceAlt (zebra row) values match Windows SettingsWindow.cpp PaletteForTheme exactly.
  if (theme == 1) { // 暖白
    p.ink = rgb(243, 241, 235); p.surface = rgb(252, 251, 248); p.surfaceAlt = rgb(238, 235, 227); p.surfaceHover = rgb(234, 231, 224);
    p.border = rgb(208, 203, 193); p.text = rgb(26, 27, 30); p.muted = rgb(122, 120, 113);
  } else if (theme == 2) { // 石墨
    p.ink = rgb(21, 23, 28); p.surface = rgb(30, 33, 40); p.surfaceAlt = rgb(46, 51, 60); p.surfaceHover = rgb(36, 40, 48);
    p.border = rgb(54, 59, 70); p.text = rgb(244, 245, 247); p.muted = rgb(148, 154, 168);
  } else { // GY 蓝夜
    p.ink = rgb(16, 18, 22); p.surface = rgb(29, 33, 40); p.surfaceAlt = rgb(46, 51, 60); p.surfaceHover = rgb(35, 39, 47);
    p.border = rgb(52, 58, 69); p.text = rgb(250, 250, 251); p.muted = rgb(155, 163, 179);
  }
  p.accent = rgb(43, 96, 221);
  p.onAccent = rgb(250, 250, 251);
  return p;
}
@end

static NSFont *GYTitleFont(void) { return [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold]; }
static NSFont *GYControlFont(void) { return [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold]; }
static NSFont *GYAuxFont(void) { return [NSFont systemFontOfSize:10 weight:NSFontWeightRegular]; }
static CGFloat GYDefaultLineHeight(NSFont *font) {
  return ceil(font.ascender - font.descender + font.leading);
}

static void GYDrawText(NSString *text, NSRect rect, NSColor *color, NSFont *font, NSTextAlignment alignment) {
  NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
  style.alignment = alignment;
  style.lineBreakMode = NSLineBreakByTruncatingTail;
  NSDictionary *attrs = @{NSFontAttributeName: font,
                          NSForegroundColorAttributeName: color,
                          NSParagraphStyleAttributeName: style};
  const NSSize size = [text sizeWithAttributes:attrs];
  const CGFloat y = NSMinY(rect) + (NSHeight(rect) - size.height) / 2;
  [text drawWithRect:NSMakeRect(NSMinX(rect), y, NSWidth(rect), size.height)
             options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
          attributes:attrs];
}

// Compact GY wordmark, same path data as the locked brand SVG.
static void GYDrawWordmark(NSRect bounds, NSColor *color) {
  const CGFloat sx = NSWidth(bounds) / 156.0, sy = NSHeight(bounds) / 100.0;
  CGFloat (^x)(CGFloat) = ^CGFloat(CGFloat v) { return NSMinX(bounds) + v * sx; };
  CGFloat (^y)(CGFloat) = ^CGFloat(CGFloat v) { return NSMinY(bounds) + v * sy; };
  [color setFill];
  NSBezierPath *g = [NSBezierPath bezierPath];
  [g moveToPoint:NSMakePoint(x(72), y(26))];
  [g curveToPoint:NSMakePoint(x(40), y(13)) controlPoint1:NSMakePoint(x(65), y(18)) controlPoint2:NSMakePoint(x(54), y(13))];
  [g curveToPoint:NSMakePoint(x(8), y(50)) controlPoint1:NSMakePoint(x(21), y(13)) controlPoint2:NSMakePoint(x(8), y(28))];
  [g curveToPoint:NSMakePoint(x(40), y(87)) controlPoint1:NSMakePoint(x(8), y(72)) controlPoint2:NSMakePoint(x(21), y(87))];
  [g curveToPoint:NSMakePoint(x(72), y(63)) controlPoint1:NSMakePoint(x(56), y(87)) controlPoint2:NSMakePoint(x(68), y(77))];
  [g lineToPoint:NSMakePoint(x(72), y(52))];
  [g lineToPoint:NSMakePoint(x(40), y(52))];
  [g lineToPoint:NSMakePoint(x(40), y(66))];
  [g lineToPoint:NSMakePoint(x(57), y(66))];
  [g curveToPoint:NSMakePoint(x(40), y(74)) controlPoint1:NSMakePoint(x(54), y(72)) controlPoint2:NSMakePoint(x(48), y(74))];
  [g curveToPoint:NSMakePoint(x(21), y(50)) controlPoint1:NSMakePoint(x(28), y(74)) controlPoint2:NSMakePoint(x(21), y(64))];
  [g curveToPoint:NSMakePoint(x(40), y(26)) controlPoint1:NSMakePoint(x(21), y(36)) controlPoint2:NSMakePoint(x(28), y(26))];
  [g curveToPoint:NSMakePoint(x(60), y(37)) controlPoint1:NSMakePoint(x(49), y(26)) controlPoint2:NSMakePoint(x(56), y(31))];
  [g lineToPoint:NSMakePoint(x(72), y(26))];
  [g closePath];
  [g fill];
  NSBezierPath *yp = [NSBezierPath bezierPath];
  [yp moveToPoint:NSMakePoint(x(80), y(15))];
  [yp lineToPoint:NSMakePoint(x(94), y(15))];
  [yp lineToPoint:NSMakePoint(x(114), y(50))];
  [yp lineToPoint:NSMakePoint(x(134), y(15))];
  [yp lineToPoint:NSMakePoint(x(148), y(15))];
  [yp lineToPoint:NSMakePoint(x(121), y(60))];
  [yp lineToPoint:NSMakePoint(x(121), y(87))];
  [yp lineToPoint:NSMakePoint(x(107), y(87))];
  [yp lineToPoint:NSMakePoint(x(107), y(60))];
  [yp closePath];
  [yp fill];
}

// MARK: - Reusable custom-drawn controls (blocks keep the file self-contained)

@interface GYClickView : NSView
@property(nonatomic, copy) void (^onClick)(void);
@end
@implementation GYClickView
- (void)mouseUp:(NSEvent *)event {
  if (NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds) && self.onClick) self.onClick();
}
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }
@end

@interface GYButtonView : GYClickView
@property(nonatomic, strong) GYPalette *palette;
@property(nonatomic, copy) NSString *title;
@property(nonatomic) BOOL primary;
@end
@implementation GYButtonView
- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSColor *bg = self.primary ? self.palette.accent : self.palette.surface;
  [bg setFill];
  [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:8 yRadius:8] fill];
  if (!self.primary) {
    [self.palette.border setStroke];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:8 yRadius:8] stroke];
  }
  GYDrawText(self.title, self.bounds, self.primary ? self.palette.onAccent : self.palette.text,
             GYControlFont(), NSTextAlignmentCenter);
}
@end

@interface GYNavItemView : GYClickView
@property(nonatomic, strong) GYPalette *palette;
@property(nonatomic, copy) NSString *title;
@property(nonatomic) BOOL selected;
@property(nonatomic) NSInteger pageIndex;
@end
@implementation GYNavItemView
- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  GYDrawText(self.title, self.bounds, self.selected ? self.palette.text : self.palette.muted,
             GYControlFont(), NSTextAlignmentCenter);
  if (self.selected) {
    [self.palette.accent setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSWidth(self.bounds) - 7, 8, 7, NSHeight(self.bounds) - 16)
                                     xRadius:3 yRadius:3] fill];
  }
}
@end

@interface GYSegmentView : NSView
@property(nonatomic, strong) GYPalette *palette;
@property(nonatomic, strong) NSArray<NSString *> *items;
@property(nonatomic) NSInteger selectedIndex;
@property(nonatomic, copy) void (^onSelect)(NSInteger index);
@end
@implementation GYSegmentView
- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  [self.palette.surface setFill];
  [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:9 yRadius:9] fill];
  [self.palette.border setStroke];
  [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:9 yRadius:9] stroke];
  const CGFloat w = NSWidth(self.bounds) / self.items.count;
  for (NSUInteger i = 0; i < self.items.count; ++i) {
    const NSRect cell = NSMakeRect(i * w, 0, w, NSHeight(self.bounds));
    if ((NSInteger)i == self.selectedIndex) {
      [self.palette.accent setFill];
      [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(cell, 3, 3) xRadius:7 yRadius:7] fill];
    } else if (i > 0) {
      [self.palette.border setFill];
      NSRectFill(NSMakeRect(NSMinX(cell), 8, 1, NSHeight(self.bounds) - 16));
    }
    GYDrawText(self.items[i], cell, (NSInteger)i == self.selectedIndex ? self.palette.onAccent : self.palette.text,
               GYControlFont(), NSTextAlignmentCenter);
  }
}
- (void)mouseUp:(NSEvent *)event {
  const NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
  if (!NSPointInRect(p, self.bounds) || self.items.count == 0) return;
  const NSInteger index = MIN((NSInteger)self.items.count - 1, (NSInteger)(p.x / (NSWidth(self.bounds) / self.items.count)));
  if (self.onSelect) self.onSelect(index);
}
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }
@end

@interface GYCardView : NSView
@property(nonatomic, strong) GYPalette *palette;
@property(nonatomic) CGFloat radius;
// Per-entry zebra striping (clipboard history list), matching Windows
// SettingsWindow.cpp's row_fill = index % 2 == 0 ? pal.surface : pal.surface_alt.
@property(nonatomic) BOOL altRow;
@end
@implementation GYCardView
- (BOOL)isFlipped { return YES; } // children use top-down coordinates
- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  [(self.altRow ? self.palette.surfaceAlt : self.palette.surface) setFill];
  [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:self.radius yRadius:self.radius] fill];
  [self.palette.border setStroke];
  [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:self.radius yRadius:self.radius] stroke];
}
@end

@interface GYThemeCardView : GYClickView
@property(nonatomic, strong) GYPalette *palette;
@property(nonatomic, copy) NSString *title;
@property(nonatomic) NSInteger themeIndex;
@property(nonatomic) BOOL selected;
@end
@implementation GYThemeCardView
- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  const CGFloat radius = 8;
  [(self.selected ? self.palette.surfaceHover : self.palette.surface) setFill];
  [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:radius yRadius:radius] fill];
  [(self.selected ? self.palette.accent : self.palette.border) setStroke];
  NSBezierPath *frame = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:radius yRadius:radius];
  [frame stroke];
  // Fixed preview swatch; deliberately does not follow the settings palette.
  const NSRect swatch = NSMakeRect(12, 9, 100, 30);
  NSColor *swatchBg, *swatchText;
  if (self.themeIndex == 1) {
    swatchBg = [NSColor colorWithSRGBRed:246 / 255.0 green:244 / 255.0 blue:239 / 255.0 alpha:1];
    swatchText = [NSColor colorWithSRGBRed:26 / 255.0 green:27 / 255.0 blue:30 / 255.0 alpha:1];
  } else if (self.themeIndex == 2) {
    swatchBg = [NSColor colorWithSRGBRed:21 / 255.0 green:23 / 255.0 blue:28 / 255.0 alpha:1];
    swatchText = [NSColor colorWithSRGBRed:244 / 255.0 green:245 / 255.0 blue:247 / 255.0 alpha:1];
  } else {
    swatchBg = [NSColor colorWithSRGBRed:17 / 255.0 green:27 / 255.0 blue:46 / 255.0 alpha:1];
    swatchText = [NSColor colorWithSRGBRed:246 / 255.0 green:248 / 255.0 blue:252 / 255.0 alpha:1];
  }
  [swatchBg setFill];
  [[NSBezierPath bezierPathWithRoundedRect:swatch xRadius:5 yRadius:5] fill];
  GYDrawText(@"GY   1   2   3", swatch, swatchText, GYAuxFont(), NSTextAlignmentCenter);
  GYDrawText(self.title, NSMakeRect(124, 0, 160, NSHeight(self.bounds)), self.palette.text, GYControlFont(), NSTextAlignmentLeft);
  GYDrawText(self.selected ? @"●" : @"○", NSMakeRect(NSWidth(self.bounds) - 36, 0, 24, NSHeight(self.bounds)),
             self.selected ? self.palette.accent : self.palette.muted, GYControlFont(), NSTextAlignmentCenter);
}
@end

@interface GYSwitchView : NSView
@property(nonatomic, strong) GYPalette *palette;
@property(nonatomic) BOOL on;
@property(nonatomic, copy) void (^onToggle)(BOOL on);
@end

@implementation GYSwitchView
- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  const CGFloat height = NSHeight(self.bounds);
  const CGFloat knob = height - 6;
  NSColor *track = self.on ? self.palette.accent : self.palette.border;
  [track setFill];
  [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:height / 2 yRadius:height / 2] fill];
  [self.palette.onAccent setFill];
  const CGFloat x = self.on ? NSWidth(self.bounds) - knob - 3 : 3;
  [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x, 3, knob, knob)] fill];
}
- (void)mouseUp:(NSEvent *)event {
  const NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  if (!NSPointInRect(point, self.bounds)) return;
  self.on = !self.on;
  [self setNeedsDisplay:YES];
  if (self.onToggle) self.onToggle(self.on);
}
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }
@end
// MARK: - Root view (background, header, nav, footer)

@interface GYFlippedView : NSView
@end
@implementation GYFlippedView
- (BOOL)isFlipped { return YES; } // page content lays out top-down
@end

@interface GYSettingsRootView : NSView
@property(nonatomic, strong) GYPalette *palette;
@property(nonatomic) NSInteger selectedPage;
@property(nonatomic, copy) NSArray<NSString *> *pages;
@end

@implementation GYSettingsRootView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  [self.palette.ink setFill];
  NSRectFill(self.bounds);
  [self.palette.border setStroke];
  [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:14 yRadius:14] stroke];
  GYDrawWordmark(NSMakeRect(24, 25, 52, 33), self.palette.text);
  GYDrawText(@"输入法设置", NSMakeRect(90, 24, 300, 22), self.palette.text, GYTitleFont(), NSTextAlignmentLeft);
  GYDrawText(@"基础输入始终离线可用", NSMakeRect(90, 48, 300, 14), self.palette.muted, GYAuxFont(), NSTextAlignmentLeft);
  GYDrawText(@"所有基础输入设置仅保存在本机", NSMakeRect(24, kWindowH - 24 - 42, 260, 42),
             self.palette.muted, GYAuxFont(), NSTextAlignmentLeft);
  // Every test build must be self-identifying from the running app alone —
  // no version label here meant nobody could tell which build was installed
  // without reaching for a terminal.
  NSDictionary *info = NSBundle.mainBundle.infoDictionary;
  NSString *marketing = info[@"CFBundleShortVersionString"] ?: @"?";
  NSString *build = info[@"CFBundleVersion"] ?: @"?";
  GYDrawText([NSString stringWithFormat:@"v%@ (%@)", marketing, build],
             NSMakeRect(24, kWindowH - 24 - 42 + 18, 260, 16),
             self.palette.muted, GYAuxFont(), NSTextAlignmentLeft);
}
@end

// MARK: - Preferences controller

@interface GYPreferencesController () <NSTextFieldDelegate>
@end

// NSWindowStyleMaskBorderless 的窗口，canBecomeKeyWindow 默认返回 NO：
// makeKeyAndOrderFront: 会被 AppKit 拒绝（日志里是
// "makeKeyWindow called on ... which returned NO from canBecomeKeyWindow"），
// 窗口拿不到 key，里面任何 NSTextField 都无法获得焦点——点不进去也打不了字。
// 设置面板要收邮箱和密码，就必须能成为 key window。
@interface GYSettingsWindow : NSWindow
@end
@implementation GYSettingsWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end

@implementation GYPreferencesController {
  NSWindow *_window;
  GYSettingsRootView *_rootView;
  NSView *_contentView;
  NSInteger _page;
  NSDictionary *_snapshot;
  NSTextField *_accountField;
  // Phrases card state
  BOOL _phrasesEditing;
  NSTextView *_phrasesEditor;
  GYCardView *_phrasesCard;
  GYClickView *_phrasesToggle;
  BOOL _phrasesToggleIsFinish;
  NSScrollView *_clipboardScroll;
  NSView *_clipboardListView;
  // GY 账户登录卡状态
  NSTextField *_loginEmailField;
  NSSecureTextField *_loginPasswordField;
  NSString *_loginEmailDraft;
  NSString *_loginError;
}

// 剪贴板页与账户页的页码，供通知回调判断是否需要重建。
enum { kGYAccountPageIndex = 3, kGYClipboardPageIndex = 4 };

+ (instancetype)sharedController {
  static GYPreferencesController *controller;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ controller = [[GYPreferencesController alloc] init]; });
  return controller;
}

- (instancetype)init {
  self = [super init];
  if (!self) return nil;
  _loginEmailDraft = @"";
  // 账户状态变化要重画登录卡与剪贴板页的状态行。
  // 剪贴板历史变化只重画剪贴板页——后台同步合并时若连账户页一起重建，
  // 会把用户正在输入的密码清掉。
  [NSNotificationCenter.defaultCenter addObserver:self
                                         selector:@selector(gyAccountDidChange:)
                                             name:GYAccountAuthDidChangeNotification
                                           object:nil];
  [NSNotificationCenter.defaultCenter addObserver:self
                                         selector:@selector(gyClipboardDidChange:)
                                             name:GYClipboardHistory.didChangeNotification
                                           object:nil];
  return self;
}

- (void)gyAccountDidChange:(NSNotification *)notification {
  (void)notification;
  if (!_window.isVisible) return;
  if (_page == kGYAccountPageIndex || _page == kGYClipboardPageIndex) [self rebuildPage];
}

- (void)gyClipboardDidChange:(NSNotification *)notification {
  (void)notification;
  if (!_window.isVisible || _page != kGYClipboardPageIndex) return;
  [self rebuildPage];
}

- (GYPalette *)palette { return [GYPalette forTheme:GYSettingsStore.sharedStore.candidateTheme]; }

- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)show {
  [self captureSnapshot];
  _page = 0;
  _phrasesEditing = NO;
  if (_window == nil) [self buildWindow];
  [self reloadChrome];
  [_window center];
  [_window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
}

- (void)showAbout { [self show]; }

- (void)captureSnapshot {
  GYSettingsStore *store = GYSettingsStore.sharedStore;
  _snapshot = @{
    @"mode": @(store.inputMode),
    @"theme": @(store.candidateTheme),
    @"fontSize": @(store.candidateFontSize),
    @"phrases": store.customPhrases,
    @"accountName": store.accountName,
  };
}

- (void)restoreSnapshot {
  GYSettingsStore *store = GYSettingsStore.sharedStore;
  store.inputMode = (GYInputMode)[_snapshot[@"mode"] integerValue];
  store.candidateTheme = [_snapshot[@"theme"] integerValue];
  store.candidateFontSize = [_snapshot[@"fontSize"] integerValue];
  store.accountName = _snapshot[@"accountName"];
  [store clearCustomPhrases];
  NSDictionary<NSString *, NSArray<NSString *> *> *phrases = _snapshot[@"phrases"];
  for (NSString *code in phrases) [store setCustomPhrases:phrases[code] forCode:code];
}

- (BOOL)isDirty {
  GYSettingsStore *store = GYSettingsStore.sharedStore;
  return store.inputMode != (GYInputMode)[_snapshot[@"mode"] integerValue] ||
         store.candidateTheme != [_snapshot[@"theme"] integerValue] ||
         store.candidateFontSize != [_snapshot[@"fontSize"] integerValue] ||
         ![store.accountName isEqualToString:_snapshot[@"accountName"]] ||
         ![store.customPhrases isEqualToDictionary:_snapshot[@"phrases"]];
}

- (void)buildWindow {
  _window = [[GYSettingsWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWindowW, kWindowH)
                                                styleMask:NSWindowStyleMaskBorderless
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
  _window.level = NSFloatingWindowLevel;
  _window.opaque = NO;
  _window.backgroundColor = NSColor.clearColor;
  _window.hasShadow = YES;
  _window.movableByWindowBackground = YES;
  _window.releasedWhenClosed = NO;

  _rootView = [[GYSettingsRootView alloc] initWithFrame:NSMakeRect(0, 0, kWindowW, kWindowH)];
  _rootView.wantsLayer = YES;
  _rootView.layer.cornerRadius = 14;
  _rootView.layer.masksToBounds = YES;
  _rootView.pages = @[@"通用", @"输入", @"外观", @"账户", @"剪贴板"];
  _window.contentView = _rootView;
  [NSNotificationCenter.defaultCenter addObserver:self
                                         selector:@selector(clipboardHistoryDidChange:)
                                             name:GYClipboardHistory.didChangeNotification
                                           object:GYClipboardHistory.sharedHistory];

  // × close (30×30 hot area, 18 from the top-right corner)
  GYClickView *close = [[GYClickView alloc] initWithFrame:NSMakeRect(kWindowW - 18 - 30, 18, 30, 30)];
  __weak typeof(self) weakSelf = self;
  close.onClick = ^{ [weakSelf closeDiscarding]; };
  NSTextField *closeLabel = [self labelWithText:@"✕" font:GYControlFont()];
  closeLabel.frame = NSMakeRect(0, 0, 30, 30);
  closeLabel.alignment = NSTextAlignmentCenter;
  [close addSubview:closeLabel];
  [_rootView addSubview:close];

  // Left nav: first item top 118, pitch 47
  for (NSUInteger i = 0; i < 5; ++i) {
    GYNavItemView *item = [[GYNavItemView alloc] initWithFrame:NSMakeRect(18, 118 + i * 47, 72, 30)];
    item.pageIndex = (NSInteger)i;
    item.onClick = ^{
      typeof(self) strongSelf = weakSelf;
      strongSelf->_page = item.pageIndex;
      [strongSelf reloadChrome];
    };
    [_rootView addSubview:item];
  }

  _contentView = [[GYFlippedView alloc] initWithFrame:NSMakeRect(112, 150, 384, kWindowH - 150 - 80)];
  [_rootView addSubview:_contentView];

  GYButtonView *done = [[GYButtonView alloc] initWithFrame:NSMakeRect(kWindowW - 24 - 110, kWindowH - 24 - 42, 110, 42)];
  done.primary = YES;
  done.title = @"完成";
  done.onClick = ^{ [weakSelf closeSaving]; };
  [_rootView addSubview:done];
}

- (NSTextField *)labelWithText:(NSString *)text font:(NSFont *)font {
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
  label.stringValue = text;
  label.font = font;
  label.bordered = NO;
  label.editable = NO;
  label.selectable = NO;
  label.drawsBackground = NO;
  label.textColor = NSColor.whiteColor;
  return label;
}

- (void)reloadChrome {
  GYPalette *palette = self.palette;
  _rootView.palette = palette;
  _rootView.selectedPage = _page;
  [_rootView setNeedsDisplay:YES];
  for (NSView *subview in _rootView.subviews) {
    if ([subview isKindOfClass:GYNavItemView.class]) {
      GYNavItemView *item = (GYNavItemView *)subview;
      item.palette = palette;
      item.title = _rootView.pages[item.pageIndex];
      item.selected = item.pageIndex == _page;
      [item setNeedsDisplay:YES];
    } else if ([subview isKindOfClass:GYButtonView.class]) {
      GYButtonView *button = (GYButtonView *)subview;
      button.palette = palette;
      [button setNeedsDisplay:YES];
    } else if ([subview isKindOfClass:GYClickView.class]) {
      for (NSTextField *label in subview.subviews) {
        if ([label isKindOfClass:NSTextField.class]) label.textColor = palette.muted;
      }
    }
  }
  [self rebuildPage];
}

- (void)rebuildPage {
  for (NSView *subview in [_contentView.subviews copy]) [subview removeFromSuperview];
  // 旧的输入框已经脱离视图树；清掉 ivar，避免关闭时读到已移除的控件。
  _accountField = nil;
  _loginEmailField = nil;
  _loginPasswordField = nil;
  switch (_page) {
    case 0: [self buildGeneralPage]; break;
    case 1: [self buildInputPage]; break;
    case 2: [self buildAppearancePage]; break;
    case 3: [self buildAccountPage]; break;
    case 4: [self buildClipboardPage]; break;
  }
}

- (NSTextField *)sectionLabel:(NSString *)text atY:(CGFloat)y {
  GYPalette *palette = self.palette;
  NSTextField *label = [self labelWithText:text font:GYAuxFont()];
  label.textColor = palette.muted;
  label.frame = NSMakeRect(2, y, 300, 16);
  [_contentView addSubview:label];
  return label;
}

// MARK: 通用页

- (void)buildGeneralPage {
  GYPalette *palette = self.palette;
  GYSettingsStore *store = GYSettingsStore.sharedStore;
  __weak typeof(self) weakSelf = self;

  const CGFloat cardH = _phrasesEditing ? 132 : 58;
  const CGFloat phraseCardGap = 12;
  _phrasesCard = [[GYCardView alloc] initWithFrame:NSMakeRect(0, 0, 384, cardH)];
  _phrasesCard.palette = palette;
  _phrasesCard.radius = 9;
  [_contentView addSubview:_phrasesCard];

  NSTextField *title = [self labelWithText:@"常用短语" font:GYControlFont()];
  title.textColor = palette.text;
  title.frame = NSMakeRect(16, 10, 140, 18);
  [_phrasesCard addSubview:title];

  _phrasesToggle = [[GYClickView alloc] initWithFrame:NSMakeRect(384 - 16 - 80, 10, 80, 18)];
  NSTextField *toggleLabel = [self labelWithText:_phrasesEditing ? @"完成编辑" : @"管理 ›" font:GYControlFont()];
  toggleLabel.textColor = palette.accent;
  toggleLabel.frame = NSMakeRect(0, 0, 80, 18);
  toggleLabel.alignment = NSTextAlignmentRight;
  [_phrasesToggle addSubview:toggleLabel];
  _phrasesToggle.onClick = ^{ [weakSelf togglePhrasesEditing]; };
  [_phrasesCard addSubview:_phrasesToggle];

  if (!_phrasesEditing) {
    NSString *hint = store.customPhrases.count == 0 ? @"例如：dz=地址|电子邮箱" : [self phrasesSummary];
    NSTextField *sub = [self labelWithText:hint font:GYAuxFont()];
    sub.textColor = palette.muted;
    sub.frame = NSMakeRect(16, 32, 350, 14);
    [_phrasesCard addSubview:sub];
  } else {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 36, 352, 84)];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = YES;
    scroll.backgroundColor = palette.ink;
    _phrasesEditor = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 352, 84)];
    _phrasesEditor.font = GYControlFont();
    _phrasesEditor.textColor = palette.text;
    _phrasesEditor.backgroundColor = palette.ink;
    _phrasesEditor.insertionPointColor = palette.text;
    _phrasesEditor.string = [self phrasesEditorText];
    scroll.documentView = _phrasesEditor;
    [_phrasesCard addSubview:scroll];
  }

  // Three-action bar: 清空学习 · 导出 · 导入
  const CGFloat barY = cardH + phraseCardGap;
  GYCardView *bar = [[GYCardView alloc] initWithFrame:NSMakeRect(0, barY, 384, 42)];
  bar.palette = palette;
  bar.radius = 9;
  [_contentView addSubview:bar];
  NSArray<NSString *> *actions = @[@"清空学习", @"导出", @"导入"];
  const CGFloat cellW = 384.0 / 3;
  for (NSUInteger i = 0; i < actions.count; ++i) {
    GYClickView *cell = [[GYClickView alloc] initWithFrame:NSMakeRect(i * cellW, 0, cellW, 42)];
    NSTextField *cellLabel = [self labelWithText:actions[i] font:GYControlFont()];
    cellLabel.textColor = palette.text;
    cellLabel.frame = NSMakeRect(0, 0, cellW, 42);
    cellLabel.alignment = NSTextAlignmentCenter;
    [cell addSubview:cellLabel];
    if (i == 0) cell.onClick = ^{ [weakSelf clearLearning]; };
    else if (i == 1) cell.onClick = ^{ [weakSelf exportSettings]; };
    else cell.onClick = ^{ [weakSelf importSettings]; };
    [bar addSubview:cell];
    if (i > 0) {
      NSView *divider = [[NSView alloc] initWithFrame:NSMakeRect(i * cellW, 8, 1, 42 - 16)];
      divider.wantsLayer = YES;
      divider.layer.backgroundColor = palette.border.CGColor;
      [bar addSubview:divider];
    }
  }

  // Windows 对应：剪贴板控制卡为即时生效，开关写入设置后无需点“完成”。
  const CGFloat switchY = barY + 42 + 14;
  GYCardView *sync = [[GYCardView alloc] initWithFrame:NSMakeRect(0, switchY, 384, 78)];
  sync.palette = palette;
  sync.radius = 9;
  [_contentView addSubview:sync];
  NSTextField *syncTitle = [self labelWithText:@"跨设备剪贴板" font:GYControlFont()];
  syncTitle.textColor = palette.text;
  syncTitle.frame = NSMakeRect(16, 10, 220, 18);
  [sync addSubview:syncTitle];
  NSTextField *syncSub = [self labelWithText:@"在已配对的设备间同步复制内容" font:GYAuxFont()];
  syncSub.textColor = palette.muted;
  syncSub.frame = NSMakeRect(16, 30, 300, 30);
  [sync addSubview:syncSub];
  GYSwitchView *syncSwitch = [[GYSwitchView alloc] initWithFrame:NSMakeRect(384 - 16 - 48, 26, 48, 26)];
  syncSwitch.palette = palette;
  syncSwitch.on = store.clipboardSyncEnabled;
  // 经 GYKeepSync 落设置：它除了写 store 还要唤醒/停下同步循环。
  syncSwitch.onToggle = ^(BOOL on) { [GYKeepSync.sharedSync setEnabled:on]; };
  [sync addSubview:syncSwitch];

  GYCardView *instant = [[GYCardView alloc] initWithFrame:NSMakeRect(0, switchY + 78 + 14, 384, 78)];
  instant.palette = palette;
  instant.radius = 9;
  [_contentView addSubview:instant];
  NSTextField *instantTitle = [self labelWithText:@"即时粘贴" font:GYControlFont()];
  instantTitle.textColor = palette.text;
  instantTitle.frame = NSMakeRect(16, 10, 220, 18);
  [instant addSubview:instantTitle];
  NSTextField *instantSub = [self labelWithText:@"我复制的内容直接写入其他设备的剪贴板，Ctrl+V / ⌘V 即可粘贴" font:GYAuxFont()];
  instantSub.textColor = palette.muted;
  instantSub.frame = NSMakeRect(16, 28, 300, 16);
  [instant addSubview:instantSub];
  NSTextField *instantTip = [self labelWithText:@"关闭后，收到的内容只进入剪贴板历史，需手动选择" font:GYAuxFont()];
  instantTip.textColor = palette.muted;
  instantTip.frame = NSMakeRect(16, 44, 300, 14);
  [instant addSubview:instantTip];
  GYSwitchView *instantSwitch = [[GYSwitchView alloc] initWithFrame:NSMakeRect(384 - 16 - 48, 26, 48, 26)];
  instantSwitch.palette = palette;
  instantSwitch.on = store.clipboardInstantPaste;
  // 同上；重新打开时它会清掉 lastAppliedRemoteHeadId，
  // 让当前远端最新一条补写一次系统剪贴板。
  instantSwitch.onToggle = ^(BOOL on) { [GYKeepSync.sharedSync setInstantPasteEnabled:on]; };
  [instant addSubview:instantSwitch];
}

- (NSString *)phrasesSummary {
  NSDictionary<NSString *, NSArray<NSString *> *> *phrases = GYSettingsStore.sharedStore.customPhrases;
  NSString *code = phrases.allKeys.firstObject;
  if (code == nil) return @"例如：dz=地址|电子邮箱";
  return [NSString stringWithFormat:@"%@=%@", code, [phrases[code] componentsJoinedByString:@"|"]];
}

- (NSString *)phrasesEditorText {
  NSDictionary<NSString *, NSArray<NSString *> *> *phrases = GYSettingsStore.sharedStore.customPhrases;
  NSMutableArray<NSString *> *lines = [NSMutableArray array];
  for (NSString *code in [phrases.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
    [lines addObject:[NSString stringWithFormat:@"%@=%@", code, [phrases[code] componentsJoinedByString:@"|"]]];
  }
  return [lines componentsJoinedByString:@"\n"];
}

- (void)togglePhrasesEditing {
  if (_phrasesEditing) {
    if (![self applyPhrasesEditorText]) return; // stay open on invalid input
  }
  _phrasesEditing = !_phrasesEditing;
  [self rebuildPage];
}

- (BOOL)applyPhrasesEditorText {
  GYSettingsStore *store = GYSettingsStore.sharedStore;
  NSMutableDictionary<NSString *, NSArray<NSString *> *> *parsed = [NSMutableDictionary dictionary];
  for (NSString *line in [_phrasesEditor.string componentsSeparatedByString:@"\n"]) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (trimmed.length == 0) continue;
    const NSRange equals = [trimmed rangeOfString:@"="];
    if (equals.location == NSNotFound || equals.location == 0) {
      [self alertMessage:[NSString stringWithFormat:@"短语格式不正确：%@\n应为 编码=短语1|短语2", trimmed]];
      return NO;
    }
    NSString *code = [[trimmed substringToIndex:equals.location] lowercaseString];
    NSMutableArray<NSString *> *list = [NSMutableArray array];
    for (NSString *part in [[trimmed substringFromIndex:equals.location + 1] componentsSeparatedByString:@"|"]) {
      NSString *phrase = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
      if (phrase.length != 0) [list addObject:phrase];
    }
    if (list.count == 0) {
      [self alertMessage:[NSString stringWithFormat:@"编码 %@ 没有短语内容。", code]];
      return NO;
    }
    parsed[code] = list;
  }
  [store clearCustomPhrases];
  for (NSString *code in parsed) [store setCustomPhrases:parsed[code] forCode:code];
  return YES;
}

- (void)clearLearning {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"清空本机的所有候选学习记录？常用短语不会受影响。";
  [alert addButtonWithTitle:@"清空"];
  [alert addButtonWithTitle:@"取消"];
  if ([alert runModal] != NSAlertFirstButtonReturn) return;
  NSError *error = nil;
  if (![GYRimeBridge moveLearningDatabaseToTrash:&error]) {
    [self alertMessage:[NSString stringWithFormat:@"清空学习失败：%@", error.localizedDescription]];
  }
}

- (void)exportSettings {
  NSSavePanel *panel = [NSSavePanel savePanel];
  panel.nameFieldStringValue = @"gy-settings.json";
  if ([panel runModal] != NSModalResponseOK) return;
  NSDictionary *backup = [GYSettingsStore.sharedStore portableSettingsBackup];
  NSData *data = [NSJSONSerialization dataWithJSONObject:backup options:NSJSONWritingPrettyPrinted error:nil];
  [data writeToURL:panel.URL atomically:YES];
}

- (void)importSettings {
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  panel.allowedFileTypes = @[@"json"];
  if ([panel runModal] != NSModalResponseOK) return;
  NSData *data = [NSData dataWithContentsOfURL:panel.URL];
  if (data == nil || data.length > 64 * 1024) {
    [self alertMessage:@"设置备份无效或过大。仅接受不超过 64 KB 的 GY 设置文件。"];
    return;
  }
  id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (![parsed isKindOfClass:NSDictionary.class]) {
    [self alertMessage:@"设置备份无效或过大。仅接受不超过 64 KB 的 GY 设置文件。"];
    return;
  }
  // Back up the live settings file before applying the imported one.
  GYSettingsStore *store = GYSettingsStore.sharedStore;
  NSURL *support = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                        inDomains:NSUserDomainMask] firstObject];
  NSURL *live = [[support URLByAppendingPathComponent:@"GYInput"] URLByAppendingPathComponent:@"settings.json"];
  NSURL *backupURL = [[support URLByAppendingPathComponent:@"GYInput"] URLByAppendingPathComponent:@"settings.backup.json"];
  [NSFileManager.defaultManager removeItemAtURL:backupURL error:nil];
  [NSFileManager.defaultManager copyItemAtURL:live toURL:backupURL error:nil];
  NSError *error = nil;
  if (![store importPortableSettingsBackup:parsed error:&error]) {
    [self alertMessage:error.localizedDescription ?: @"设置备份无效。"];
    return;
  }
  [self reloadChrome]; // theme/mode may have changed; repaint immediately
}

// MARK: 输入页

- (void)buildInputPage {
  GYPalette *palette = self.palette;
  GYSettingsStore *store = GYSettingsStore.sharedStore;
  __weak typeof(self) weakSelf = self;
  [self sectionLabel:@"输入语言" atY:6];
  GYSegmentView *segment = [[GYSegmentView alloc] initWithFrame:NSMakeRect(0, 26, 384, 42)];
  segment.palette = palette;
  segment.items = @[@"简体", @"繁体", @"EN"];
  segment.selectedIndex = (NSInteger)store.inputMode;
  segment.onSelect = ^(NSInteger index) {
    GYSettingsStore.sharedStore.inputMode = (GYInputMode)index;
    [weakSelf reloadChrome];
  };
  [_contentView addSubview:segment];

  GYCardView *rule = [[GYCardView alloc] initWithFrame:NSMakeRect(0, 80, 384, 58)];
  rule.palette = palette;
  rule.radius = 9;
  [_contentView addSubview:rule];
  NSTextField *title = [self labelWithText:@"切换规则" font:GYControlFont()];
  title.textColor = palette.text;
  title.frame = NSMakeRect(16, 8, 200, 18);
  [rule addSubview:title];
  NSTextField *body = [self labelWithText:@"Shift 快速切换 EN；EN 模式下字母、标点、Enter 与快捷键原样直出。" font:GYAuxFont()];
  body.textColor = palette.muted;
  body.frame = NSMakeRect(16, 30, 352, 16);
  [rule addSubview:body];

  GYCardView *warm = [[GYCardView alloc] initWithFrame:NSMakeRect(0, 144, 384, 94)];
  warm.palette = palette;
  warm.radius = 9;
  [_contentView addSubview:warm];
  NSTextField *warmTitle = [self labelWithText:@"热启动加速" font:GYControlFont()];
  warmTitle.textColor = palette.text;
  warmTitle.frame = NSMakeRect(16, 8, 180, 18);
  [warm addSubview:warmTitle];
  NSTextField *warmBody = [self labelWithText:@"开启后引擎保持热连接，按键零等待；关闭后每次按键重新握手。" font:GYAuxFont()];
  warmBody.textColor = palette.muted;
  warmBody.frame = NSMakeRect(16, 28, 300, 20);
  [warmBody.cell setWraps:YES];
  [warm addSubview:warmBody];
  NSTextField *warmBody2 = [self labelWithText:@"建议 4 核 CPU / 8 GB 内存及以上开启；更低配置的设备请关闭。" font:GYAuxFont()];
  warmBody2.textColor = palette.muted;
  warmBody2.frame = NSMakeRect(16, 48, 300, 20);
  [warmBody2.cell setWraps:YES];
  [warm addSubview:warmBody2];
  GYSwitchView *warmSwitch = [[GYSwitchView alloc] initWithFrame:NSMakeRect(384 - 16 - 48, 34, 48, 26)];
  warmSwitch.palette = palette;
  warmSwitch.on = store.warmStartEnabled;
  warmSwitch.onToggle = ^(BOOL on) { store.warmStartEnabled = on; };
  [warm addSubview:warmSwitch];
}

- (void)buildAppearancePage {
  GYPalette *palette = self.palette;
  GYSettingsStore *store = GYSettingsStore.sharedStore;
  __weak typeof(self) weakSelf = self;
  [self sectionLabel:@"候选窗主题" atY:6];
  NSArray<NSString *> *names = @[@"GY 蓝夜", @"暖白", @"石墨"];
  for (NSUInteger i = 0; i < names.count; ++i) {
    GYThemeCardView *card = [[GYThemeCardView alloc] initWithFrame:NSMakeRect(0, 26 + i * 56, 384, 48)];
    card.palette = palette;
    card.title = names[i];
    card.themeIndex = (NSInteger)i;
    card.selected = store.candidateTheme == (NSInteger)i;
    card.onClick = ^{
      GYSettingsStore.sharedStore.candidateTheme = (NSInteger)i;
      [weakSelf reloadChrome]; // settings window repaints in the new theme at once
    };
    [_contentView addSubview:card];
  }
  [self sectionLabel:@"候选字大小" atY:26 + 3 * 56 + 4];
  GYSegmentView *sizes = [[GYSegmentView alloc] initWithFrame:NSMakeRect(0, 26 + 3 * 56 + 24, 384, 42)];
  sizes.palette = palette;
  sizes.items = @[@"紧凑", @"默认", @"大"];
  const NSInteger fontSize = store.candidateFontSize;
  sizes.selectedIndex = fontSize <= 13 ? 0 : fontSize >= 17 ? 2 : 1;
  sizes.onSelect = ^(NSInteger index) {
    GYSettingsStore.sharedStore.candidateFontSize = index == 0 ? 13 : index == 2 ? 17 : 15;
  };
  [_contentView addSubview:sizes];

  const CGFloat aiY = 26 + 3 * 56 + 24 + 42 + 16;
  GYCardView *ai = [[GYCardView alloc] initWithFrame:NSMakeRect(0, aiY, 384, 136)];
  ai.palette = palette;
  ai.radius = 10;
  [_contentView addSubview:ai];
  NSTextField *title = [self labelWithText:@"AI 外观预览助手" font:GYControlFont()];
  title.textColor = palette.text;
  title.frame = NSMakeRect(16, 10, 240, 18);
  [ai addSubview:title];
  NSTextField *sub = [self labelWithText:@"可根据你的描述生成预览；确认前不会更改任何设置。" font:GYAuxFont()];
  sub.textColor = palette.muted;
  sub.frame = NSMakeRect(16, 30, 340, 14);
  [ai addSubview:sub];
  NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 52, 352, 34)];
  input.placeholderString = @"例如：更安静一点，字稍微大一点";
  input.font = GYControlFont();
  input.textColor = palette.text;
  input.bordered = NO;
  input.drawsBackground = YES;
  input.backgroundColor = palette.ink;
  input.wantsLayer = YES;
  input.layer.cornerRadius = 7;
  input.layer.borderWidth = 1;
  input.layer.borderColor = palette.border.CGColor;
  input.enabled = NO; // v1 占位：不接网络、不产生请求
  [ai addSubview:input];
  NSTextField *note = [self labelWithText:@"只可建议主题、字号与对比度；不会修改 Logo、候选窗箭头、布局或输入交互。" font:GYAuxFont()];
  note.textColor = palette.muted;
  note.frame = NSMakeRect(16, 96, 352, 28);
  note.cell.wraps = YES;
  [ai addSubview:note];
}

// MARK: 账户页

- (void)buildClipboardPage {
  GYPalette *palette = self.palette;
  __weak typeof(self) weakSelf = self;

  // 连接状态：Keep 是权威层，这一行必须如实反映能不能同步。
  NSString *statusText;
  if (GYAccountAuth.sharedAuth.status != GYAccountStatusLoggedIn) {
    statusText = @"登录 GY 账户后可同步到 Keep";
  } else if (!GYSettingsStore.sharedStore.clipboardSyncEnabled) {
    statusText = @"Keep 同步已关闭 · 仅保存在本机";
  } else {
    statusText = @"已连接 Keep · 自动同步中";
  }
  NSTextField *statusLabel = [self labelWithText:statusText font:GYAuxFont()];
  statusLabel.textColor = palette.muted;
  statusLabel.frame = NSMakeRect(2, 8, 300, 14);
  [_contentView addSubview:statusLabel];

  const CGFloat toolbarHeight = 34;
  _clipboardScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, toolbarHeight, 384, _contentView.bounds.size.height - toolbarHeight)];
  _clipboardScroll.hasVerticalScroller = YES;
  _clipboardScroll.drawsBackground = NO;

  _clipboardListView = [[GYFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 384, _clipboardScroll.bounds.size.height)];
  [_clipboardScroll setDocumentView:_clipboardListView];

  const CGFloat clearWidth = 56;
  GYClickView *clear = [[GYClickView alloc] initWithFrame:NSMakeRect(384 - 16 - clearWidth, 0, clearWidth, 26)];
  NSTextField *clearLabel = [self labelWithText:@"清空" font:GYAuxFont()];
  clearLabel.textColor = palette.accent;
  clearLabel.frame = clear.bounds;
  clearLabel.alignment = NSTextAlignmentCenter;
  [clear addSubview:clearLabel];
  clear.onClick = ^{ [weakSelf clearClipboardHistory]; };
  [_contentView addSubview:clear];




  [_contentView addSubview:_clipboardScroll];

  [self reloadClipboardCardsWithPalette:palette];
}

- (NSInteger)clipboardLineCountForText:(NSString *)text width:(CGFloat)width {
  NSFont *font = GYAuxFont();
  const CGFloat lineHeight = GYDefaultLineHeight(font);
  NSRect measured = [text boundingRectWithSize:NSMakeSize(width, CGFLOAT_MAX)
                                       options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                    attributes:@{NSFontAttributeName: font}
                                       context:nil];
  return MIN(4, MAX(1, (NSInteger)ceil(NSHeight(measured) / lineHeight)));
}

- (CGFloat)clipboardCardHeightForLineCount:(NSInteger)lineCount {
  const CGFloat lineHeight = GYDefaultLineHeight(GYAuxFont());
  const CGFloat textHeight = lineCount * lineHeight + (lineCount - 1) * 4;
  return 10 + textHeight + 8 + 16 + 8;
}

- (void)reloadClipboardCardsWithPalette:(GYPalette *)palette {
  if (_clipboardListView == nil) return;
  for (NSView *sub in [_clipboardListView.subviews copy]) [sub removeFromSuperview];

  NSArray<GYClipboardEntry *> *entries = GYClipboardHistory.sharedHistory.entries;
  const CGFloat cardWidth = 384;
  const CGFloat textWidth = cardWidth - 32;
  const CGFloat gap = 12;
  const CGFloat sidePad = 0;
  const CGFloat lineHeight = GYDefaultLineHeight(GYAuxFont());

  if (entries.count == 0) {
    NSTextField *empty = [self labelWithText:@"还没有剪贴板历史，复制一段文字试试" font:GYAuxFont()];
    empty.textColor = palette.muted;
    empty.alignment = NSTextAlignmentCenter;
    empty.frame = NSMakeRect(0, 80, cardWidth, 20);
    [_clipboardListView addSubview:empty];
    _clipboardListView.frame = NSMakeRect(0, 0, cardWidth, 120);
    return;
  }

  CGFloat y = 0;
  NSInteger entryIndex = 0;
  for (GYClipboardEntry *entry in entries) {
    NSString *displayText = entry.text.length == 0 ? @"（空白内容已过滤）" : entry.text;
    const NSInteger lineCount = [self clipboardLineCountForText:displayText width:textWidth];
    const CGFloat cardHeight = [self clipboardCardHeightForLineCount:lineCount];
    const CGFloat textHeight = lineCount * lineHeight + (lineCount - 1) * 4;

    GYCardView *card = [[GYCardView alloc] initWithFrame:NSMakeRect(sidePad, y, cardWidth, cardHeight)];
    card.palette = palette;
    card.radius = 10;
    card.altRow = (entryIndex % 2) != 0;
    ++entryIndex;
    [_clipboardListView addSubview:card];

    NSTextField *text = [self labelWithText:displayText font:GYAuxFont()];
    text.textColor = palette.text;
    text.frame = NSMakeRect(16, 10, textWidth, textHeight);
    text.cell.wraps = YES;
    text.maximumNumberOfLines = lineCount;
    text.lineBreakMode = NSLineBreakByTruncatingTail;
    text.alignment = NSTextAlignmentLeft;
    [card addSubview:text];

    NSTextField *time = [self labelWithText:[self formatClipboardTime:entry.unixTime] font:GYAuxFont()];
    time.textColor = palette.muted;
    time.alignment = NSTextAlignmentLeft;
    time.frame = NSMakeRect(16, cardHeight - 24, textWidth, 16);
    [card addSubview:time];

    y += cardHeight + gap;
  }

  const CGFloat totalHeight = MAX(0, y - gap);
  _clipboardListView.frame = NSMakeRect(0, 0, cardWidth, MAX(_clipboardScroll.bounds.size.height, totalHeight));
}
- (NSString *)formatClipboardTime:(NSTimeInterval)unix {
  static NSDateFormatter *formatter = nil;
  if (formatter == nil) {
    formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm";
  }
  return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:unix]];
}

- (void)clearClipboardHistory {
  NSAlert *alert = [[NSAlert alloc] init];
  // Keep 是权威层：清空只影响本机，而且下一轮同步会把 Keep 的最新 20 条拉回来。
  // 文案必须说清楚，不能让用户以为这是在删云端记录。
  alert.messageText = @"清空此 Mac 的本机历史？Keep 中的内容不会删除。";
  alert.informativeText = @"下次同步会重新拉取 Keep 中最新的 20 条。";
  [alert addButtonWithTitle:@"清空"];
  [alert addButtonWithTitle:@"取消"];
  if ([alert runModal] != NSAlertFirstButtonReturn) return;
  [GYClipboardHistory.sharedHistory clear];
  [self reloadClipboardCardsWithPalette:self.palette];
}

- (void)clipboardHistoryDidChange:(NSNotification *)note {
  (void)note;
  if (_page != 4 || _window == nil || !_window.isVisible) return;
  GYPalette *palette = self.palette;
  [self reloadClipboardCardsWithPalette:palette];
}
- (void)buildAccountPage {
  GYPalette *palette = self.palette;
  GYSettingsStore *store = GYSettingsStore.sharedStore;
  GYCardView *account = [[GYCardView alloc] initWithFrame:NSMakeRect(0, 0, 384, 52)];
  account.palette = palette;
  account.radius = 9;
  [_contentView addSubview:account];
  NSTextField *title = [self labelWithText:@"账号" font:GYControlFont()];
  title.textColor = palette.text;
  title.frame = NSMakeRect(16, 8, 112, 18);
  [account addSubview:title];
  NSTextField *sub = [self labelWithText:@"本地标识" font:GYAuxFont()];
  sub.textColor = palette.muted;
  sub.frame = NSMakeRect(16, 28, 112, 14);
  [account addSubview:sub];
  _accountField = [[NSTextField alloc] initWithFrame:NSMakeRect(128, 10, 384 - 128 - 16, 32)];
  _accountField.placeholderString = @"输入邮箱，例如 name@example.com";
  _accountField.stringValue = store.accountName;
  _accountField.font = GYControlFont();
  _accountField.textColor = palette.text;
  _accountField.bordered = NO;
  _accountField.drawsBackground = YES;
  _accountField.backgroundColor = palette.ink;
  _accountField.wantsLayer = YES;
  _accountField.layer.cornerRadius = 7;
  _accountField.layer.borderWidth = 1;
  _accountField.layer.borderColor = palette.border.CGColor;
  _accountField.delegate = self;
  [account addSubview:_accountField];

  const GYAccountStatus status = GYAccountAuth.sharedAuth.status;
  const BOOL signedIn = status == GYAccountStatusLoggedIn;
  const BOOL busy = status == GYAccountStatusLoggingIn;

  GYCardView *gy = [[GYCardView alloc] initWithFrame:NSMakeRect(0, 64, 384, signedIn ? 146 : 194)];
  gy.palette = palette;
  gy.radius = 9;
  [_contentView addSubview:gy];
  NSTextField *gyTitle = [self labelWithText:@"GY 账户" font:GYControlFont()];
  gyTitle.textColor = palette.text;
  gyTitle.frame = NSMakeRect(16, 12, 200, 18);
  [gy addSubview:gyTitle];

  __weak typeof(self) weakSelf = self;
  if (signedIn) {
    NSTextField *email = [self labelWithText:GYAccountAuth.sharedAuth.email font:GYControlFont()];
    email.textColor = palette.text;
    email.frame = NSMakeRect(16, 36, 340, 18);
    email.lineBreakMode = NSLineBreakByTruncatingTail;
    [gy addSubview:email];

    NSTextField *connected = [self labelWithText:@"已连接 Keep" font:GYAuxFont()];
    connected.textColor = palette.accent;
    connected.frame = NSMakeRect(16, 58, 340, 14);
    [gy addSubview:connected];

    NSTextField *note = [self labelWithText:@"会话仅保存在这台 Mac 的加密钥匙串中" font:GYAuxFont()];
    note.textColor = palette.muted;
    note.frame = NSMakeRect(16, 78, 340, 14);
    [gy addSubview:note];

    GYButtonView *logout = [[GYButtonView alloc] initWithFrame:NSMakeRect(16, 100, 110, 34)];
    logout.palette = palette;
    logout.title = @"退出登录";
    logout.onClick = ^{ [weakSelf performLogout]; };
    [gy addSubview:logout];
    return;
  }

  NSTextField *gyBody = [self labelWithText:@"登录后，复制内容会自动同步到 Keep" font:GYAuxFont()];
  gyBody.textColor = palette.muted;
  gyBody.frame = NSMakeRect(16, 32, 340, 16);
  [gy addSubview:gyBody];

  _loginEmailField = [self loginFieldWithPlaceholder:@"邮箱" secure:NO frame:NSMakeRect(16, 54, 352, 30)];
  _loginEmailField.stringValue = _loginEmailDraft ?: @"";
  _loginEmailField.enabled = !busy;
  [gy addSubview:_loginEmailField];

  _loginPasswordField =
      (NSSecureTextField *)[self loginFieldWithPlaceholder:@"密码" secure:YES frame:NSMakeRect(16, 90, 352, 30)];
  _loginPasswordField.enabled = !busy;
  [gy addSubview:_loginPasswordField];

  if (_loginError.length != 0) {
    NSTextField *error = [self labelWithText:_loginError font:GYAuxFont()];
    error.textColor = [NSColor colorWithSRGBRed:229 / 255.0 green:83 / 255.0 blue:75 / 255.0 alpha:1];
    error.frame = NSMakeRect(16, 126, 352, 14);
    [gy addSubview:error];
  }

  GYButtonView *login = [[GYButtonView alloc] initWithFrame:NSMakeRect(16, 146, 110, 34)];
  login.palette = palette;
  login.primary = YES;
  login.title = busy ? @"登录中…" : @"登录";
  if (!busy) login.onClick = ^{ [weakSelf performLogin]; };
  [gy addSubview:login];
}

- (NSTextField *)loginFieldWithPlaceholder:(NSString *)placeholder
                                    secure:(BOOL)secure
                                     frame:(NSRect)frame {
  GYPalette *palette = self.palette;
  NSTextField *field =
      secure ? [[NSSecureTextField alloc] initWithFrame:frame] : [[NSTextField alloc] initWithFrame:frame];
  field.placeholderString = placeholder;
  field.font = GYControlFont();
  field.textColor = palette.text;
  field.bordered = NO;
  field.drawsBackground = YES;
  field.backgroundColor = palette.ink;
  field.wantsLayer = YES;
  field.layer.cornerRadius = 7;
  field.layer.borderWidth = 1;
  field.layer.borderColor = palette.border.CGColor;
  return field;
}

- (void)performLogin {
  // 登录按钮是自绘的 GYClickView，不是 NSButton：点击它不会把第一响应者
  // 从文本框拿走，字段编辑器仍持有用户刚输入的内容，此时 stringValue 返回的
  // 是上一次提交的值（通常是空）。必须先强制结束编辑再读。
  [_window makeFirstResponder:nil];
  NSString *email = _loginEmailField.stringValue ?: @"";
  NSString *password = _loginPasswordField.stringValue ?: @"";
  _loginEmailDraft = email;
  _loginError = nil;
  __weak typeof(self) weakSelf = self;
  [GYAccountAuth.sharedAuth loginWithEmail:email
                                  password:password
                                completion:^(BOOL success, NSString *message) {
                                  typeof(self) self_ = weakSelf;
                                  if (self_ == nil) return;
                                  self_->_loginError = success ? nil : message;
                                  if (success) self_->_loginEmailDraft = @"";
                                  [GYKeepSync.sharedSync accountDidChange];
                                  if (self_->_page == kGYAccountPageIndex) [self_ rebuildPage];
                                }];
  [self rebuildPage];  // 立刻画出禁用/登录中状态
}

- (void)performLogout {
  // 只忘掉这台 Mac 上的会话；不删除 Keep 里的任何笔记。
  [GYAccountAuth.sharedAuth logout];
  [GYKeepSync.sharedSync accountDidChange];
  _loginError = nil;
  _loginEmailDraft = @"";
  [self rebuildPage];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
  if (notification.object == _accountField) {
    GYSettingsStore.sharedStore.accountName = _accountField.stringValue;
  }
}

// MARK: Close semantics

- (void)closeSaving {
  if (_accountField != nil) GYSettingsStore.sharedStore.accountName = _accountField.stringValue;
  [_window close];
}

- (void)closeDiscarding {
  if (_accountField != nil) GYSettingsStore.sharedStore.accountName = _accountField.stringValue;
  if ([self isDirty]) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"有未保存的修改，关闭将丢弃这些修改。";
    [alert addButtonWithTitle:@"丢弃修改"];
    [alert addButtonWithTitle:@"继续编辑"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [self restoreSnapshot];
  }
  [_window close];
}

- (void)alertMessage:(NSString *)message {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = message;
  [alert addButtonWithTitle:@"好"];
  [alert runModal];
}

@end
