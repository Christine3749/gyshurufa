#import "GYCandidatePanel.h"
#import "GYDiagnostics.h"
#import <math.h>

static NSColor *GYColor(NSUInteger rgb) { return [NSColor colorWithSRGBRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1]; }
static NSFont *GYFont(CGFloat size) { return [NSFont systemFontOfSize:size weight:NSFontWeightSemibold]; }
static NSString *GYModeText(GYInputMode mode) { return mode == GYInputModeTraditional ? @"繁" : mode == GYInputModeEnglish ? @"EN" : @"简"; }

@interface GYCandidateWindow : NSPanel @end
@implementation GYCandidateWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface GYCandidateSurface : NSView
@property(copy) NSArray<NSString *> *candidates;
@property(copy) GYCandidateActionHandler handler;
@property NSArray<NSValue *> *candidateFrames;
@property NSRect toggleFrame, previousFrame, nextFrame, modeFrame;
@property NSInteger selection;
@property GYInputMode mode;
@property BOOL expanded, expandable, previous, next;
- (instancetype)initWithHandler:(GYCandidateActionHandler)handler;
- (void)configure:(NSArray<NSString *> *)candidates selection:(NSInteger)selection mode:(GYInputMode)mode expanded:(BOOL)expanded expandable:(BOOL)expandable previous:(BOOL)previous next:(BOOL)next;
- (NSSize)preferredSize;
@end

@implementation GYCandidateSurface
- (instancetype)initWithHandler:(GYCandidateActionHandler)handler {
  if ((self = [super initWithFrame:NSMakeRect(0, 0, 1, 1)])) _handler = [handler copy];
  return self;
}
- (BOOL)isFlipped { return YES; }
- (void)configure:(NSArray<NSString *> *)candidates selection:(NSInteger)selection mode:(GYInputMode)mode expanded:(BOOL)expanded expandable:(BOOL)expandable previous:(BOOL)previous next:(BOOL)next {
  _candidates = [candidates copy]; _selection = selection; _mode = mode; _expanded = expanded; _expandable = expandable; _previous = previous; _next = next;
  [self preferredSize]; [self setNeedsDisplay:YES];
}
- (NSSize)preferredSize {
  CGFloat pad = 6, gap = 3, height = 29, x = pad, bottom = pad + height;
  NSMutableArray *frames = [NSMutableArray array]; _toggleFrame = _previousFrame = _nextFrame = _modeFrame = NSZeroRect;
  if (_expanded) {
    CGFloat cell = 106; NSUInteger rows = (_candidates.count + 4) / 5;
    for (NSUInteger index = 0; index < _candidates.count; index++) {
      NSUInteger row = index / 5, column = index % 5;
      [frames addObject:[NSValue valueWithRect:NSMakeRect(pad + column * (cell + gap), pad + row * (height + gap), cell, height)]];
    }
    bottom = pad + rows * height + (rows ? (rows - 1) * gap : 0) + gap;
    _toggleFrame = NSMakeRect(pad, bottom, 24, height);
    _modeFrame = NSMakeRect(NSMaxX(_toggleFrame) + gap, bottom, 34, height);
    if (_previous || _next) {
      _nextFrame = NSMakeRect(pad + 5 * (cell + gap) - gap - 24, bottom, 24, height);
      _previousFrame = NSMakeRect(NSMinX(_nextFrame) - gap - 24, bottom, 24, height);
    }
    bottom += height + pad; x = pad + 5 * cell + 4 * gap;
  } else {
    NSDictionary *attributes = @{NSFontAttributeName: GYFont(15)};
    for (NSString *candidate in _candidates) {
      CGFloat width = MAX(64, ceil([candidate sizeWithAttributes:attributes].width) + 30);
      NSRect frame = NSMakeRect(x, pad, width, height); [frames addObject:[NSValue valueWithRect:frame]]; x = NSMaxX(frame) + gap;
    }
    if (_expandable) { _toggleFrame = NSMakeRect(x, pad, 24, height); x = NSMaxX(_toggleFrame) + gap + 1; }
    _modeFrame = NSMakeRect(x, pad, 34, height); x = NSMaxX(_modeFrame); bottom = height + 2 * pad;
  }
  _candidateFrames = frames; return NSMakeSize(MAX(70, x + pad), bottom);
}
- (void)drawText:(NSString *)text in:(NSRect)rect font:(NSFont *)font color:(NSColor *)color alignment:(NSTextAlignment)alignment {
  NSMutableParagraphStyle *style = [NSMutableParagraphStyle new]; style.alignment = alignment; style.lineBreakMode = NSLineBreakByClipping;
  [text drawInRect:NSInsetRect(rect, 0, 5) withAttributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: style}];
}
- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect; NSRect bounds = self.bounds; [GYColor(0x111318) setFill]; NSRectFill(bounds);
  [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, .5, .5) xRadius:9 yRadius:9] setLineWidth:1]; [GYColor(0x31353D) setStroke]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, .5, .5) xRadius:9 yRadius:9] stroke];
  NSColor *white = GYColor(0xF6F8FC), *muted = GYColor(0x979DA9), *blue = GYColor(0x2863EB), *disclosure = GYColor(0x5280E2);
  for (NSUInteger index = 0; index < _candidateFrames.count; index++) {
    NSRect frame = _candidateFrames[index].rectValue; BOOL selected = index == _selection;
    if (selected) { [blue setFill]; [[NSBezierPath bezierPathWithRoundedRect:frame xRadius:6 yRadius:6] fill]; }
    BOOL shortcut = !_expanded || index < 5;
    [self drawText:shortcut ? [NSString stringWithFormat:@"%lu", (unsigned long)index + 1] : @"" in:NSMakeRect(NSMinX(frame) + 5, NSMinY(frame), 15, NSHeight(frame)) font:GYFont(10) color:selected ? white : muted alignment:NSTextAlignmentCenter];
    [self drawText:_candidates[index] in:NSMakeRect(NSMinX(frame) + 21, NSMinY(frame), NSWidth(frame) - 26, NSHeight(frame)) font:GYFont(15) color:selected ? white : white alignment:NSTextAlignmentLeft];
  }
  if (!NSIsEmptyRect(_toggleFrame)) {
    CGFloat divider = NSMaxX(_toggleFrame) + 1; [GYColor(0x31353D) setFill]; NSRectFill(NSMakeRect(divider, NSMinY(_toggleFrame) + 7, 1, NSHeight(_toggleFrame) - 14));
    CGFloat x = _expanded ? NSMidX(_toggleFrame) : NSMinX(_toggleFrame) + 8, y = _expanded ? NSMidY(_toggleFrame) : NSMaxY(_toggleFrame) - 8;
    NSBezierPath *chevron = [NSBezierPath bezierPath]; [chevron moveToPoint:NSMakePoint(x - 5, y + (_expanded ? 3 : -3))]; [chevron lineToPoint:NSMakePoint(x, y + (_expanded ? -3 : 3))]; [chevron lineToPoint:NSMakePoint(x + 5, y + (_expanded ? 3 : -3))]; [chevron setLineWidth:1.5]; [disclosure setStroke]; [chevron stroke];
  }
  [self drawText:GYModeText(_mode) in:_modeFrame font:GYFont(12) color:disclosure alignment:NSTextAlignmentCenter];
  if (_expanded && (_previous || _next)) {
    [self drawText:@"↑" in:_previousFrame font:GYFont(17) color:_previous ? disclosure : muted alignment:NSTextAlignmentCenter];
    [self drawText:@"↓" in:_nextFrame font:GYFont(17) color:_next ? disclosure : muted alignment:NSTextAlignmentCenter];
  }
}
- (void)mouseUp:(NSEvent *)event {
  NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  for (NSUInteger index = 0; index < _candidateFrames.count; index++) if (NSPointInRect(point, _candidateFrames[index].rectValue)) { _handler(GYCandidateActionSelect, index); return; }
  if (NSPointInRect(point, _toggleFrame)) { _handler(GYCandidateActionToggle, 0); return; }
  if (_previous && NSPointInRect(point, _previousFrame)) { _handler(GYCandidateActionPrevious, 0); return; }
  if (_next && NSPointInRect(point, _nextFrame)) _handler(GYCandidateActionNext, 0);
}
@end

static NSRange GYCaretRange(id client) {
  NSRange range = NSMakeRange(NSNotFound, 0);
  if ([client respondsToSelector:@selector(markedRange)]) range = [client markedRange];
  if (range.location != NSNotFound && range.length) return NSMakeRange(NSMaxRange(range), 0);
  if ([client respondsToSelector:@selector(selectedRange)]) return [client selectedRange];
  return range;
}

static NSScreen *GYScreenForCaret(NSRect caret) {
  NSPoint point = NSMakePoint(NSMinX(caret), NSMinY(caret));
  for (NSScreen *screen in NSScreen.screens) {
    if (NSIntersectsRect(caret, screen.frame) || NSPointInRect(point, screen.frame)) return screen;
  }
  return nil;
}

static BOOL GYCaretIsUsable(NSRect caret) {
  return isfinite(NSMinX(caret)) && isfinite(NSMinY(caret)) && isfinite(NSHeight(caret)) &&
      NSHeight(caret) > 0 && !NSEqualRects(caret, NSZeroRect) &&
      !(fabs(NSMinX(caret)) < 1 && fabs(NSMinY(caret)) < 1);
}

@implementation GYCandidatePanel { GYCandidateWindow *_window; GYCandidateSurface *_surface; NSUInteger _generation; }
- (instancetype)initWithActionHandler:(GYCandidateActionHandler)handler {
  if ((self = [super init])) {
    _surface = [[GYCandidateSurface alloc] initWithHandler:handler];
    _window = [[GYCandidateWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1, 1) styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    _window.contentView = _surface; _window.opaque = YES; _window.hasShadow = NO; _window.backgroundColor = GYColor(0x111318);
    _window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorTransient;
  }
  return self;
}
- (void)showCandidates:(NSArray<NSString *> *)candidates selection:(NSInteger)selection mode:(GYInputMode)mode expanded:(BOOL)expanded expandable:(BOOL)expandable previous:(BOOL)previous next:(BOOL)next client:(id)client {
  [_surface configure:candidates selection:selection mode:mode expanded:expanded expandable:expandable previous:previous next:next];
  NSUInteger generation = ++_generation; [_window orderOut:nil];
  __weak GYCandidatePanel *weakSelf = self; __weak id weakClient = client;
  dispatch_async(dispatch_get_main_queue(), ^{
    GYCandidatePanel *strongSelf = weakSelf; id strongClient = weakClient;
    if (strongSelf == nil || generation != strongSelf->_generation) return;
    [strongSelf showPositionedCandidatesForClient:strongClient];
  });
}
- (void)showPositionedCandidatesForClient:(id)client {
  if (![client respondsToSelector:@selector(firstRectForCharacterRange:actualRange:)]) { [self hide]; return; }
  NSRange range = GYCaretRange(client);
  NSRect caret = range.location == NSNotFound ? NSZeroRect : [client firstRectForCharacterRange:range actualRange:NULL];
  NSScreen *screen = GYCaretIsUsable(caret) ? GYScreenForCaret(caret) : nil;
  if (screen == nil) {
    GYTrace([NSString stringWithFormat:@"candidate-anchor=unusable client=%@ range=%lu,%lu x=%.0f y=%.0f w=%.0f h=%.0f",
             NSStringFromClass([client class]), (unsigned long)range.location, (unsigned long)range.length,
             NSMinX(caret), NSMinY(caret), NSWidth(caret), NSHeight(caret)]);
    NSPoint mouse = [NSEvent mouseLocation];
    caret = NSMakeRect(mouse.x, mouse.y, 1, 20);
    screen = GYScreenForCaret(caret) ?: NSScreen.mainScreen;
  }
  if (screen == nil) { GYTrace(@"candidate-anchor=unavailable"); [self hide]; return; }
  NSSize size = _surface.preferredSize;
  GYTrace([NSString stringWithFormat:@"candidate-anchor client=%@ x=%.0f y=%.0f h=%.0f", NSStringFromClass([client class]), NSMinX(caret), NSMinY(caret), NSHeight(caret)]);
  NSRect visible = screen.visibleFrame;
  CGFloat maxX = MAX(NSMinX(visible), NSMaxX(visible) - size.width), maxY = MAX(NSMinY(visible), NSMaxY(visible) - size.height);
  CGFloat x = MIN(MAX(NSMinX(caret), NSMinX(visible)), maxX), y = NSMinY(caret) - size.height - 5;
  if (y < NSMinY(visible)) y = NSMaxY(caret) + 5;
  y = MIN(MAX(y, NSMinY(visible)), maxY);
  if ([client respondsToSelector:@selector(windowLevel)]) _window.level = [client windowLevel] + 1;
  [_window setFrame:NSMakeRect(x, y, size.width, size.height) display:YES]; [_window orderFront:nil];
}
- (void)hide { _generation++; [_window orderOut:nil]; }
@end
