#import "GYCandidatePanel.h"
#import "GYSettingsStore.h"
#import <Carbon/Carbon.h>

// Match the density of the native WeChat strip: 27pt content, 2.5pt outside
// breathing room. At 2× this is a 64px-high control rather than the old,
// noticeably loose 92px candidate bar.
static const CGFloat GYPanelOuterRadius = 8.0;
static const CGFloat GYPanelChipRadius = 5.0;
static const CGFloat GYPanelPadding = 2.5;
static const CGFloat GYPanelGap = 2.0;
static const CGFloat GYPanelRowHeight = 27.0;
static const NSUInteger GYPanelColumns = 5;
static const NSUInteger GYPanelMaximumRows = 5;
// Keep the cell-sizing and the text-drawing geometry in one place.  The
// compact strip previously reserved 22pt beyond a word's measured width, but
// the renderer consumed 23pt.  That one-point deficit is enough for AppKit to
// clip the final Han glyph in two-character candidates (for example, 优雅).
static const CGFloat GYPanelCandidateTextX = 19.0;
static const CGFloat GYPanelCandidateTextRightInset = 5.0;
static const CGFloat GYPanelCandidateTextSafetyInset = 2.0;

static NSColor *GYPanelColor(CGFloat red, CGFloat green, CGFloat blue) {
  return [NSColor colorWithSRGBRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:1.0];
}
// These are deliberately the same three themes as native/src/CandidateWindow.cpp
// in the Windows build.  Keep every colour here in sync with that source instead
// of inventing a separate macOS palette.
static NSColor *GYPanelBackground(NSInteger theme) {
  return theme == 1 ? GYPanelColor(252, 252, 251) : GYPanelColor(17, 19, 24);
}
static NSColor *GYPanelBorder(NSInteger theme) {
  if (theme == 1) return GYPanelColor(225, 229, 235);
  return theme == 2 ? GYPanelColor(52, 57, 67) : GYPanelColor(49, 53, 61);
}
static NSColor *GYPanelText(NSInteger theme) {
  return theme == 1 ? GYPanelColor(17, 19, 24) : GYPanelColor(246, 248, 252);
}
static NSColor *GYPanelMuted(NSInteger theme) {
  if (theme == 1) return GYPanelColor(96, 108, 122);
  return theme == 2 ? GYPanelColor(148, 158, 174) : GYPanelColor(151, 157, 169);
}
static NSColor *GYPanelSelectedBackground(NSInteger theme) {
  return theme == 2 ? GYPanelColor(72, 81, 96) : GYPanelColor(40, 99, 235);
}
static NSColor *GYPanelBlue(void) { return GYPanelColor(40, 99, 235); }

@interface GYCandidatePanelWindow : NSPanel
@end

@implementation GYCandidatePanelWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }
@end

@interface GYCandidateStripView : NSView
@property(nonatomic, copy) NSArray<NSString *> *candidates;
@property(nonatomic) NSUInteger selectedIndex;
@property(nonatomic) BOOL canGoPreviousPage;
@property(nonatomic) BOOL canGoNextPage;
@property(nonatomic) BOOL expanded;
@property(nonatomic) BOOL canExpandCandidates;
@property(nonatomic) BOOL modePopup;
@property(nonatomic, copy) NSString *inputModeTitle;
@property(nonatomic, copy) GYCandidatePanelSelectionHandler selectionHandler;
@property(nonatomic, copy) GYCandidatePanelActionHandler previousPageHandler;
@property(nonatomic, copy) GYCandidatePanelActionHandler nextPageHandler;
@property(nonatomic, copy) GYCandidatePanelActionHandler toggleExpandedHandler;
@property(nonatomic, copy) GYCandidatePanelActionHandler openSettingsHandler;
@property(nonatomic, copy) NSArray<NSValue *> *candidateRects;
@property(nonatomic) NSRect previousPageRect;
@property(nonatomic) NSRect nextPageRect;
@property(nonatomic) NSRect expandRect;
@property(nonatomic) NSRect modeRect;
- (NSSize)preferredSize;
@end

@implementation GYCandidateStripView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _candidates = @[];
    _inputModeTitle = @"简";
    _candidateRects = @[];
    self.wantsLayer = YES;
  }
  return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }

- (NSDictionary<NSAttributedStringKey, id> *)candidateAttributesWithColor:(NSColor *)color {
  // Use the native Chinese UI face explicitly.  Apart from matching the
  // surrounding macOS typography, this prevents a fallback-font mismatch in
  // the IME process from rendering otherwise valid Han candidates as tofu.
  NSFont *font = [NSFont fontWithName:@"PingFangSC-Semibold" size:16.0] ?:
      [NSFont systemFontOfSize:16.0 weight:NSFontWeightSemibold];
  return @{ NSFontAttributeName: font,
            NSForegroundColorAttributeName: color };
}

- (NSDictionary<NSAttributedStringKey, id> *)keyAttributesWithColor:(NSColor *)color alignment:(NSTextAlignment)alignment {
  NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
  style.alignment = alignment;
  style.lineBreakMode = NSLineBreakByClipping;
  return @{ NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:10.0 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: color,
            NSParagraphStyleAttributeName: style };
}

- (CGFloat)collapsedChipWidthForCandidate:(NSString *)candidate {
  CGFloat textWidth = ceil([candidate sizeWithAttributes:[self candidateAttributesWithColor:GYPanelText(GYSettingsStore.sharedStore.candidateTheme)]].width);
  // The compact strip controls the number of visible choices, never the
  // number of Han characters inside one choice.  Do not cap this width: a
  // phrase must remain whole instead of losing its final characters.
  return MAX(44.0, GYPanelCandidateTextX + textWidth +
                    GYPanelCandidateTextRightInset +
                    GYPanelCandidateTextSafetyInset);
}

- (CGFloat)expandedGridCellWidth {
  CGFloat widestText = 0.0;
  NSDictionary *attributes = [self candidateAttributesWithColor:GYPanelText(GYSettingsStore.sharedStore.candidateTheme)];
  for (NSString *candidate in self.candidates) {
    widestText = MAX(widestText, ceil([candidate sizeWithAttributes:attributes].width));
  }
  // 90pt preserves the dense Windows-style rhythm for ordinary one- to
  // four-character choices. Longer phrases grow the cell instead of being
  // clipped or silently truncated.
  return MAX(90.0, GYPanelCandidateTextX + widestText +
                    GYPanelCandidateTextRightInset +
                    GYPanelCandidateTextSafetyInset);
}

- (NSUInteger)gridRows {
  return MAX(1, MIN(GYPanelMaximumRows, (self.candidates.count + GYPanelColumns - 1) / GYPanelColumns));
}

- (NSSize)preferredSize {
  if (self.modePopup) {
    // Match the Windows mode confirmation: one compact, noninteractive badge
    // beside the caret, with enough room for the wider EN label.
    const CGFloat labelWidth = ceil([self.inputModeTitle sizeWithAttributes:
        [self keyAttributesWithColor:GYPanelBlue() alignment:NSTextAlignmentCenter]].width);
    return NSMakeSize(MAX(38.0, labelWidth + 18.0), GYPanelRowHeight + GYPanelPadding * 2.0);
  }
  if (self.expanded) {
    const CGFloat gridWidth = [self expandedGridCellWidth];
    const CGFloat width = GYPanelPadding * 2.0 + gridWidth * GYPanelColumns + GYPanelGap * (GYPanelColumns - 1);
    const CGFloat rows = (CGFloat)[self gridRows];
    const CGFloat height = GYPanelPadding * 2.0 + rows * GYPanelRowHeight +
        (rows - 1.0) * GYPanelGap + GYPanelGap + GYPanelRowHeight;
    return NSMakeSize(width, height);
  }
  CGFloat width = GYPanelPadding;
  for (NSString *candidate in self.candidates) width += [self collapsedChipWidthForCandidate:candidate] + GYPanelGap;
  if (self.candidates.count > 0) width -= GYPanelGap;
  if (self.canExpandCandidates) width += 22.0 + GYPanelGap;
  width += 34.0 + GYPanelPadding;
  return NSMakeSize(ceil(MAX(110.0, width)), GYPanelRowHeight + GYPanelPadding * 2.0);
}

- (void)layoutControls {
  NSMutableArray<NSValue *> *rects = [NSMutableArray arrayWithCapacity:self.candidates.count];
  self.previousPageRect = NSZeroRect;
  self.nextPageRect = NSZeroRect;
  self.expandRect = NSZeroRect;
  self.modeRect = NSZeroRect;
  if (self.modePopup) {
    self.modeRect = NSInsetRect(self.bounds, GYPanelPadding, GYPanelPadding);
    self.candidateRects = rects;
    return;
  }
  if (self.expanded) {
    const CGFloat cellWidth = [self expandedGridCellWidth];
    const NSUInteger rows = [self gridRows];
    for (NSUInteger index = 0; index < self.candidates.count; ++index) {
      NSUInteger row = index / GYPanelColumns;
      NSUInteger column = index % GYPanelColumns;
      if (row >= GYPanelMaximumRows) break;
      [rects addObject:[NSValue valueWithRect:NSMakeRect(
          GYPanelPadding + column * (cellWidth + GYPanelGap),
          GYPanelPadding + row * (GYPanelRowHeight + GYPanelGap),
          cellWidth, GYPanelRowHeight)]];
    }
    const CGFloat controlsTop = GYPanelPadding + rows * GYPanelRowHeight + (rows - 1) * GYPanelGap + GYPanelGap;
    self.expandRect = NSMakeRect(GYPanelPadding, controlsTop, 22.0, GYPanelRowHeight);
    self.modeRect = NSMakeRect(NSMaxX(self.expandRect) + GYPanelGap, controlsTop, 30.0, GYPanelRowHeight);
    self.nextPageRect = NSMakeRect(self.bounds.size.width - GYPanelPadding - 16.0, controlsTop, 16.0, GYPanelRowHeight);
    self.previousPageRect = NSMakeRect(NSMinX(self.nextPageRect) - 20.0, controlsTop, 16.0, GYPanelRowHeight);
  } else {
    CGFloat x = GYPanelPadding;
    for (NSString *candidate in self.candidates) {
      CGFloat candidateWidth = [self collapsedChipWidthForCandidate:candidate];
      NSRect rect = NSMakeRect(x, GYPanelPadding, candidateWidth, GYPanelRowHeight);
      [rects addObject:[NSValue valueWithRect:rect]];
      x = NSMaxX(rect) + GYPanelGap;
    }
    if (self.canExpandCandidates) {
      self.expandRect = NSMakeRect(x, GYPanelPadding, 22.0, GYPanelRowHeight);
      x = NSMaxX(self.expandRect) + GYPanelGap;
    }
    self.modeRect = NSMakeRect(x + 2.0, GYPanelPadding, 30.0, GYPanelRowHeight);
  }
  self.candidateRects = rects;
}

- (void)drawDividerAtX:(CGFloat)x top:(CGFloat)top height:(CGFloat)height {
  [GYPanelBorder(GYSettingsStore.sharedStore.candidateTheme) setFill];
  NSRectFill(NSMakeRect(x, top + 5.0, 1.0, height - 10.0));
}

- (void)drawChevronInRect:(NSRect)rect pointingUp:(BOOL)pointingUp color:(NSColor *)color {
  // This is deliberately a path, not the ⌃/⌄ glyph.  The Windows strip uses
  // a short, light chevron; a system text glyph is too tall and visually
  // heavy next to the hairline divider.
  const CGFloat halfWidth = 4.0;
  const CGFloat halfHeight = 2.7;
  // The expanding (down) chevron uses the Windows anchor: a little left of
  // centre and deliberately low in its control cell.  A centred glyph made
  // the compact strip look vertically loose next to the mode divider.
  const CGFloat centerX = pointingUp ? round(NSMidX(rect)) + 0.5 : round(NSMinX(rect) + 8.0) + 0.5;
  const CGFloat centerY = pointingUp ? round(NSMidY(rect)) + 0.5 : round(NSMaxY(rect) - 8.0) + 0.5;
  NSBezierPath *path = [NSBezierPath bezierPath];
  if (pointingUp) {
    [path moveToPoint:NSMakePoint(centerX - halfWidth, centerY + halfHeight)];
    [path lineToPoint:NSMakePoint(centerX, centerY - halfHeight)];
    [path lineToPoint:NSMakePoint(centerX + halfWidth, centerY + halfHeight)];
  } else {
    [path moveToPoint:NSMakePoint(centerX - halfWidth, centerY - halfHeight)];
    [path lineToPoint:NSMakePoint(centerX, centerY + halfHeight)];
    [path lineToPoint:NSMakePoint(centerX + halfWidth, centerY - halfHeight)];
  }
  path.lineWidth = 1.25;
  path.lineCapStyle = NSRoundLineCapStyle;
  path.lineJoinStyle = NSRoundLineJoinStyle;
  [color setStroke];
  [path stroke];
}

- (void)drawText:(NSString *)text
           inRect:(NSRect)rect
       attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes {
  // drawInRect: aligns text to the rectangle's top edge.  On Retina panels
  // that clipped descenders from Han glyphs when the chip was only one row
  // high.  Measure the actual font line and centre it instead.
  NSSize measured = [text sizeWithAttributes:attributes];
  NSRect line = rect;
  line.origin.y = floor(NSMidY(rect) - measured.height / 2.0);
  line.size.height = ceil(measured.height) + 2.0;
  [text drawInRect:line withAttributes:attributes];
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  const NSInteger theme = GYSettingsStore.sharedStore.candidateTheme;
  [self layoutControls];
  [[NSColor clearColor] setFill];
  NSRectFill(self.bounds);
  [[GYPanelBackground(theme) colorWithAlphaComponent:0.98] setFill];
  [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:GYPanelOuterRadius yRadius:GYPanelOuterRadius] fill];
  [GYPanelBorder(theme) setStroke];
  [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5)
                                   xRadius:GYPanelOuterRadius yRadius:GYPanelOuterRadius] stroke];

  for (NSUInteger index = 0; index < self.candidateRects.count; ++index) {
    NSRect chip = self.candidateRects[index].rectValue;
    BOOL selected = index == self.selectedIndex;
    if (selected) {
      [GYPanelSelectedBackground(theme) setFill];
      [[NSBezierPath bezierPathWithRoundedRect:chip xRadius:GYPanelChipRadius yRadius:GYPanelChipRadius] fill];
    }
    NSColor *foreground = selected ? NSColor.whiteColor : GYPanelText(theme);
    NSColor *shortcut = selected ? NSColor.whiteColor : GYPanelMuted(theme);
    // Match Windows: only the first row has numeric shortcuts.  A 5 × 5
    // expansion is for scanning/clicking, not a misleading 1–25 hotkey map.
    NSString *shortcutText = (!self.expanded || index < GYPanelColumns)
        ? [NSString stringWithFormat:@"%lu", (unsigned long)index + 1] : @"";
    [self drawText:shortcutText inRect:NSMakeRect(NSMinX(chip) + 3.0, NSMinY(chip), 14.0, NSHeight(chip))
        attributes:[self keyAttributesWithColor:shortcut alignment:NSTextAlignmentCenter]];
    [self drawText:self.candidates[index]
            inRect:NSMakeRect(NSMinX(chip) + GYPanelCandidateTextX, NSMinY(chip),
                              MAX(0.0, NSWidth(chip) - GYPanelCandidateTextX -
                                           GYPanelCandidateTextRightInset), NSHeight(chip))
        attributes:[self candidateAttributesWithColor:foreground]];
  }

  if (!NSIsEmptyRect(self.expandRect)) {
    if (!self.expanded) [self drawDividerAtX:NSMinX(self.expandRect) - 4.0 top:NSMinY(self.expandRect) height:NSHeight(self.expandRect)];
    [self drawChevronInRect:self.expandRect pointingUp:self.expanded color:GYPanelBlue()];
  }
  if (!NSIsEmptyRect(self.previousPageRect)) {
    if (self.expanded) {
      // In the expanded 5 × 5 panel the pager remains on the control row.
      [self drawDividerAtX:NSMinX(self.previousPageRect) - 5.0 top:NSMinY(self.previousPageRect) height:NSHeight(self.previousPageRect)];
    }
    NSColor *previousColor = self.canGoPreviousPage ? GYPanelBlue() : GYPanelMuted(theme);
    NSColor *nextColor = self.canGoNextPage ? GYPanelBlue() : GYPanelMuted(theme);
    [self drawText:@"↑" inRect:self.previousPageRect attributes:[self keyAttributesWithColor:previousColor alignment:NSTextAlignmentCenter]];
    [self drawText:@"↓" inRect:self.nextPageRect attributes:[self keyAttributesWithColor:nextColor alignment:NSTextAlignmentCenter]];
  }
  if (!NSIsEmptyRect(self.modeRect)) {
    if (!self.modePopup) {
      [self drawDividerAtX:NSMinX(self.modeRect) - 5.0 top:NSMinY(self.modeRect) height:NSHeight(self.modeRect)];
    }
    [self drawText:self.inputModeTitle inRect:self.modeRect
        attributes:[self keyAttributesWithColor:GYPanelBlue() alignment:NSTextAlignmentCenter]];
  }
}

- (void)mouseUp:(NSEvent *)event {
  NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  for (NSUInteger index = 0; index < self.candidateRects.count; ++index) {
    if (NSPointInRect(point, self.candidateRects[index].rectValue)) {
      if (self.selectionHandler) self.selectionHandler(index);
      return;
    }
  }
  if (NSPointInRect(point, self.expandRect) && self.toggleExpandedHandler) {
    self.toggleExpandedHandler();
    return;
  }
  if (NSPointInRect(point, self.previousPageRect)) {
    if (self.canGoPreviousPage && self.previousPageHandler) self.previousPageHandler();
    return;
  }
  if (NSPointInRect(point, self.nextPageRect)) {
    if (self.canGoNextPage && self.nextPageHandler) self.nextPageHandler();
    return;
  }
  if (NSPointInRect(point, self.modeRect) && self.openSettingsHandler) self.openSettingsHandler();
}

@end

@interface GYCandidatePanel ()
@property(nonatomic, strong) GYCandidatePanelWindow *window;
@property(nonatomic, strong) GYCandidateStripView *stripView;
@property(nonatomic) NSUInteger modePopupGeneration;
@end

@implementation GYCandidatePanel

- (instancetype)initWithSelectionHandler:(GYCandidatePanelSelectionHandler)selectionHandler
                     previousPageHandler:(GYCandidatePanelActionHandler)previousPageHandler
                         nextPageHandler:(GYCandidatePanelActionHandler)nextPageHandler
                    toggleExpandedHandler:(GYCandidatePanelActionHandler)toggleExpandedHandler
                    openSettingsHandler:(GYCandidatePanelActionHandler)openSettingsHandler {
  self = [super init];
  if (!self) return nil;
  _window = [[GYCandidatePanelWindow alloc] initWithContentRect:NSMakeRect(0, 0, 110, GYPanelRowHeight)
                                                      styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
  _window.opaque = NO;
  _window.backgroundColor = NSColor.clearColor;
  _window.hasShadow = YES;
  _window.movable = NO;
  _window.floatingPanel = YES;
  _window.becomesKeyOnlyIfNeeded = YES;
  _window.animationBehavior = NSWindowAnimationBehaviorNone;
  _window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
      NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorTransient;
  _stripView = [[GYCandidateStripView alloc] initWithFrame:_window.contentView.bounds];
  _stripView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  _stripView.selectionHandler = selectionHandler;
  _stripView.previousPageHandler = previousPageHandler;
  _stripView.nextPageHandler = nextPageHandler;
  _stripView.toggleExpandedHandler = toggleExpandedHandler;
  _stripView.openSettingsHandler = openSettingsHandler;
  _window.contentView = _stripView;
  return self;
}

- (NSScreen *)screenForCaretRect:(NSRect)caret {
  for (NSScreen *screen in NSScreen.screens) if (NSIntersectsRect(screen.frame, caret)) return screen;
  return NSScreen.mainScreen ?: NSScreen.screens.firstObject;
}

- (NSRect)caretRectForClient:(id)client {
  NSRect caret = NSZeroRect;
  if ([client respondsToSelector:@selector(attributesForCharacterIndex:lineHeightRectangle:)]) {
    [client attributesForCharacterIndex:0 lineHeightRectangle:&caret];
  }
  if (NSIsEmptyRect(caret) && [client respondsToSelector:@selector(firstRectForCharacterRange:actualRange:)]) {
    NSRange actual = NSMakeRange(NSNotFound, 0);
    caret = [client firstRectForCharacterRange:NSMakeRange(0, 0) actualRange:&actual];
  }
  if (NSIsEmptyRect(caret)) {
    NSPoint point = NSEvent.mouseLocation;
    caret = NSMakeRect(point.x, point.y, 1.0, 1.0);
  }
  return caret;
}

- (void)presentStripForClient:(id)client {
  NSSize size = [_stripView preferredSize];
  [_window setContentSize:size];
  [_stripView setNeedsDisplay:YES];

  NSRect caret = [self caretRectForClient:client];
  NSScreen *screen = [self screenForCaretRect:caret];
  NSRect visible = screen.visibleFrame;
  CGFloat x = MIN(MAX(NSMinX(caret), NSMinX(visible) + 4.0), NSMaxX(visible) - size.width - 4.0);
  CGFloat y = NSMinY(caret) - size.height - 5.0;
  if (y < NSMinY(visible) + 4.0) y = NSMaxY(caret) + 5.0;
  y = MIN(MAX(y, NSMinY(visible) + 4.0), NSMaxY(visible) - size.height - 4.0);
  if ([client respondsToSelector:@selector(windowLevel)]) {
    id<IMKTextInput> textClient = client;
    _window.level = (NSInteger)[textClient windowLevel] + 1;
  } else {
    _window.level = NSPopUpMenuWindowLevel;
  }
  [_window setFrame:NSMakeRect(x, y, size.width, size.height) display:YES];
  [_window orderFrontRegardless];
}

- (void)showWithCandidates:(NSArray<NSString *> *)candidates
              selectedIndex:(NSUInteger)selectedIndex
                pageNumber:(NSUInteger)pageNumber
           canGoPreviousPage:(BOOL)canGoPreviousPage
               canGoNextPage:(BOOL)canGoNextPage
                   expanded:(BOOL)expanded
        canExpandCandidates:(BOOL)canExpandCandidates
             inputModeTitle:(NSString *)inputModeTitle
                  forClient:(id)client {
  (void)pageNumber;
  if (!NSThread.isMainThread) {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      [weakSelf showWithCandidates:candidates selectedIndex:selectedIndex pageNumber:pageNumber
                 canGoPreviousPage:canGoPreviousPage canGoNextPage:canGoNextPage expanded:expanded
              canExpandCandidates:canExpandCandidates inputModeTitle:inputModeTitle forClient:client];
    });
    return;
  }
  ++_modePopupGeneration;
  // Rime and some text clients can momentarily report an array containing an
  // empty string while a composition is being created. Treat that as no
  // candidate at all: showing its selected chip produced the blue empty pill
  // at the insertion point. The Windows Host hides its UI in this state too.
  NSMutableArray<NSString *> *visibleCandidates = [NSMutableArray arrayWithCapacity:candidates.count];
  for (id value in candidates) {
    if (![value isKindOfClass:NSString.class]) continue;
    NSString *candidate = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (candidate.length != 0) [visibleCandidates addObject:candidate];
  }
  if (visibleCandidates.count == 0) {
    [self hide];
    return;
  }
  NSUInteger maximum = expanded ? GYPanelColumns * GYPanelMaximumRows : GYPanelColumns;
  _stripView.candidates = visibleCandidates.count > maximum
      ? [visibleCandidates subarrayWithRange:NSMakeRange(0, maximum)]
      : visibleCandidates;
  _stripView.selectedIndex = MIN(selectedIndex, _stripView.candidates.count == 0 ? 0 : _stripView.candidates.count - 1);
  _stripView.canGoPreviousPage = canGoPreviousPage;
  _stripView.canGoNextPage = canGoNextPage;
  _stripView.expanded = expanded;
  _stripView.canExpandCandidates = canExpandCandidates;
  _stripView.modePopup = NO;
  _stripView.inputModeTitle = inputModeTitle;
  [self presentStripForClient:client];
}

- (void)showModeTitle:(NSString *)inputModeTitle forClient:(id)client {
  if (!NSThread.isMainThread) {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf showModeTitle:inputModeTitle forClient:client]; });
    return;
  }
  ++_modePopupGeneration;
  const NSUInteger generation = _modePopupGeneration;
  _stripView.candidates = @[];
  _stripView.selectedIndex = 0;
  _stripView.canGoPreviousPage = NO;
  _stripView.canGoNextPage = NO;
  _stripView.expanded = NO;
  _stripView.canExpandCandidates = NO;
  _stripView.modePopup = YES;
  _stripView.inputModeTitle = inputModeTitle;
  [self presentStripForClient:client];

  __weak typeof(self) weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(700 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
    GYCandidatePanel *strongSelf = weakSelf;
    if (strongSelf != nil && strongSelf.modePopupGeneration == generation && strongSelf.stripView.modePopup) {
      [strongSelf hide];
    }
  });
}

- (void)hide {
  if (!NSThread.isMainThread) {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf hide]; });
    return;
  }
  ++_modePopupGeneration;
  [_window orderOut:nil];
}

@end
