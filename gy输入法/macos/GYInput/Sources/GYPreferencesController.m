#import "GYPreferencesController.h"
#import "GYSettingsStore.h"
#import "GYRimeBridge.h"
#import "GYInputMode.h"

// SETTINGS-PANEL-DESIGN.md: fixed 520×680, four pages, palette follows the
// candidate theme, only 完成 persists (× discards with a confirmation).

static const CGFloat kWindowW = 520;
static const CGFloat kWindowH = 680;

@interface GYPalette : NSObject
@property(nonatomic, strong) NSColor *ink, *surface, *surfaceHover, *border, *text, *muted, *accent, *onAccent;
+ (instancetype)forTheme:(NSInteger)theme;
@end

@implementation GYPalette
+ (instancetype)forTheme:(NSInteger)theme {
  GYPalette *p = [[GYPalette alloc] init];
  NSColor *(^rgb)(NSUInteger, NSUInteger, NSUInteger) = ^NSColor *(NSUInteger r, NSUInteger g, NSUInteger b) {
    return [NSColor colorWithSRGBRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1];
  };
  if (theme == 1) { // 暖白
    p.ink = rgb(243, 241, 235); p.surface = rgb(252, 251, 248); p.surfaceHover = rgb(234, 231, 224);
    p.border = rgb(208, 203, 193); p.text = rgb(26, 27, 30); p.muted = rgb(122, 120, 113);
  } else if (theme == 2) { // 石墨
    p.ink = rgb(21, 23, 28); p.surface = rgb(30, 33, 40); p.surfaceHover = rgb(36, 40, 48);
    p.border = rgb(54, 59, 70); p.text = rgb(244, 245, 247); p.muted = rgb(148, 154, 168);
  } else { // GY 蓝夜
    p.ink = rgb(16, 18, 22); p.surface = rgb(29, 33, 40); p.surfaceHover = rgb(35, 39, 47);
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
@end
@implementation GYCardView
- (BOOL)isFlipped { return YES; } // children use top-down coordinates
- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  [self.palette.surface setFill];
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
}
@end

// MARK: - Preferences controller

@interface GYPreferencesController () <NSTextFieldDelegate>
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
}

+ (instancetype)sharedController {
  static GYPreferencesController *controller;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ controller = [[GYPreferencesController alloc] init]; });
  return controller;
}

- (GYPalette *)palette { return [GYPalette forTheme:GYSettingsStore.sharedStore.candidateTheme]; }

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
  _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWindowW, kWindowH)
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
  _rootView.pages = @[@"通用", @"输入", @"外观", @"账户"];
  _window.contentView = _rootView;

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
  for (NSUInteger i = 0; i < 4; ++i) {
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
  switch (_page) {
    case 0: [self buildGeneralPage]; break;
    case 1: [self buildInputPage]; break;
    case 2: [self buildAppearancePage]; break;
    case 3: [self buildAccountPage]; break;
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

  // Three-action bar: 清空学习 / 导出 / 导入
  const CGFloat barY = cardH + 12;
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
}

// MARK: 外观页

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

  GYCardView *gy = [[GYCardView alloc] initWithFrame:NSMakeRect(0, 64, 384, 72)];
  gy.palette = palette;
  gy.radius = 9;
  [_contentView addSubview:gy];
  NSTextField *gyTitle = [self labelWithText:@"GY 账户" font:GYControlFont()];
  gyTitle.textColor = palette.text;
  gyTitle.frame = NSMakeRect(16, 12, 200, 18);
  [gy addSubview:gyTitle];
  NSTextField *gyBody = [self labelWithText:@"同步、跨设备词库和 AI 权益将在账户接入后开放。" font:GYAuxFont()];
  gyBody.textColor = palette.muted;
  gyBody.frame = NSMakeRect(16, 34, 340, 16);
  [gy addSubview:gyBody];
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
