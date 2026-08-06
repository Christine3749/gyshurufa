#import "GYCandidateWindow.h"
#import "GYSettingsStore.h"
#import "GYCandidateGridMath.h"

// Locked brand tokens (GY_VISUAL_IDENTITY.md / Windows CandidateWindow.cpp).
static const NSUInteger kGYInk = 0x111318;
static const NSUInteger kGYBlue = 0x2863EB;
static const NSUInteger kGYDisclosure = 0x5280E2;
static const CGFloat kDisclosureInsetX = 8;    // locked collapsed anchor
static const CGFloat kDisclosureInsetBottom = 8;

static const NSUInteger kCandidatesPerPage = 5;
static const NSUInteger kExpandedColumns = 5;  // product rule, not responsive
static const NSUInteger kExpandedMaxRows = 5;

static NSColor *GYHex(NSUInteger rgb) {
  return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0
                             green:((rgb >> 8) & 0xFF) / 255.0
                              blue:(rgb & 0xFF) / 255.0
                             alpha:1];
}

@interface GYCandidateView : NSView {
 @public
  NSArray<NSString *> *_candidates;
  NSUInteger _selected;
  NSUInteger _pageStart;
  BOOL _expanded;
  NSInteger _inputMode;
  BOOL _modePopup;
  NSInteger _theme;
  NSInteger _candidateSize;

  NSMutableArray<NSValue *> *_candidateRects;
  NSRect _modeRect, _prevRect, _nextRect, _indicatorRect, _expandRect;
  NSSize _contentSize;

  void (^_choose)(NSUInteger);
  void (^_disclosure)(BOOL);
  void (^_page)(NSInteger);
  void (^_settings)(void);
}
- (void)layoutForAvailableWidth:(CGFloat)maxWidth;
@end

@implementation GYCandidateView

- (BOOL)isFlipped { return YES; }

- (NSFont *)candidateFont { return [NSFont systemFontOfSize:_candidateSize weight:NSFontWeightSemibold]; }
- (NSFont *)keyFont { return [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold]; }
- (NSFont *)statusFont { return [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold]; }
- (NSFont *)pagerFont { return [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold]; }

- (CGFloat)measure:(NSString *)text font:(NSFont *)font {
  return [text sizeWithAttributes:@{NSFontAttributeName: font}].width;
}

- (NSString *)modeLabel { return _inputMode == 1 ? @"繁" : _inputMode == 2 ? @"EN" : @"简"; }

// Straight port of CandidateWindow::Layout (96-dpi logical values become points).
- (void)layoutForAvailableWidth:(CGFloat)maxWidth {
  const CGFloat padding = 6, gap = 3;
  const CGFloat chipH = _candidateSize + 14;
  maxWidth = MAX(180, maxWidth);
  _candidateRects = [NSMutableArray array];

  const CGFloat modeW = [self measure:self.modeLabel font:self.statusFont] + 18;
  const CGFloat pageBtnW = 26, pageIndW = 42, expandW = 24;
  const BOOL expandedGrid = _expanded && !_modePopup;
  const NSUInteger capacity = expandedGrid ? kExpandedColumns * kExpandedMaxRows : kCandidatesPerPage;
  const NSUInteger visible = (_modePopup || _pageStart >= _candidates.count)
      ? 0 : MIN(capacity, _candidates.count - _pageStart);
  const BOOL canExpand = !_modePopup && _candidates.count > kCandidatesPerPage;
  CGFloat x = MAX(0, padding - 1);
  CGFloat rightEdge = padding;
  const CGFloat nonWordW = 24;
  const CGFloat collapsedControls = _modePopup ? 0 : modeW + (canExpand ? gap + expandW : 0);
  const CGFloat totalGap = gap * (visible > 0 ? visible - 1 : 0);
  // Four Han characters are a normal word, never an overflow case.
  const CGFloat fourCharW = [self measure:@"输入法候" font:self.candidateFont];
  const CGFloat wordRoom = MAX(fourCharW,
      MAX(22, (maxWidth - x - padding - collapsedControls - totalGap) / MAX(1, (CGFloat)visible) - nonWordW));

  // Expanded mode is a fixed five-column matrix, matching Windows: do not
  // shrink it to the visible candidate count. Six candidates render as
  // 5 + 1, never 3 x 2.
  const NSUInteger gridCols = expandedGrid ? kExpandedColumns : MAX(1, visible);
  // Two-pass natural width (WINDOWS-DESIGN.md §5): measure the widest visible
  // word including the number gutter, then clamp to 82…110. Longer words fall
  // back to the ellipsis inside the 110 cell; four-character words always fit.
  // Insets (21 + 5 + 8 = 34) match Windows CandidateWindow.cpp's cell_insets.
  CGFloat naturalCell = 0;
  for (NSUInteger i = 0; i < visible; ++i) {
    naturalCell = MAX(naturalCell,
        [self measure:_candidates[_pageStart + i] font:self.candidateFont] + 34);
  }
  const CGFloat cellW = expandedGrid ? MAX(82, MIN(110, naturalCell)) : 0;

  for (NSUInteger i = 0; i < visible; ++i) {
    const CGFloat wordW = MIN([self measure:_candidates[_pageStart + i] font:self.candidateFont], wordRoom);
    const CGFloat chipW = expandedGrid ? cellW : nonWordW + wordW + 8;
    const NSUInteger row = expandedGrid ? i / gridCols : 0;
    const NSUInteger col = expandedGrid ? i % gridCols : 0;
    const CGFloat left = expandedGrid ? padding + col * (chipW + gap) : x;
    const CGFloat top = expandedGrid ? padding + row * (chipH + gap) : padding;
    [_candidateRects addObject:[NSValue valueWithRect:NSMakeRect(left, top, chipW, chipH)]];
    if (!expandedGrid) {
      x += chipW + gap;
      rightEdge = MAX(rightEdge, x - gap);
    }
  }
  // The right edge of a fixed grid must come from the grid geometry itself
  // (padding + columns * cellW + (columns-1) * gap), never from whichever
  // candidate happens to be last on a short final page — matching Windows
  // CandidateLayout::GridRight. Otherwise a 1-4 candidate last page shrinks
  // the panel and the page/prev buttons can land at negative coordinates.
  const CGFloat gridRight = expandedGrid ? GYExpandedGridRight(padding, cellW, gap, gridCols) : rightEdge;
  _modeRect = _prevRect = _nextRect = _indicatorRect = _expandRect = NSZeroRect;

  if (!_modePopup) {
    const CGFloat controlTop = expandedGrid
        ? (_candidateRects.count == 0 ? padding : NSMaxY(_candidateRects.lastObject.rectValue) + gap)
        : padding;
    if (expandedGrid) {
      // Locked order: disclosure first, then mode label.
      _expandRect = NSMakeRect(padding, controlTop, expandW, chipH);
      const CGFloat modeLeft = NSMaxX(_expandRect) + gap;
      _modeRect = NSMakeRect(modeLeft, controlTop, modeW, chipH);
      const BOOL hasMorePages = _pageStart > 0 || _pageStart + capacity < _candidates.count;
      if (hasMorePages) {
        const CGFloat nextLeft = gridRight - pageBtnW;
        _nextRect = NSMakeRect(nextLeft, controlTop, pageBtnW, chipH);
        const CGFloat indLeft = NSMinX(_nextRect) - gap - pageIndW;
        _indicatorRect = NSMakeRect(indLeft, controlTop, pageIndW, chipH);
        const CGFloat prevLeft = NSMinX(_indicatorRect) - gap - pageBtnW;
        _prevRect = NSMakeRect(prevLeft, controlTop, pageBtnW, chipH);
      }
    } else {
      // Locked order: candidates → disclosure → divider → 简/繁/EN.
      if (canExpand) {
        const CGFloat expandLeft = rightEdge + gap;
        _expandRect = NSMakeRect(expandLeft, controlTop, expandW, chipH);
        rightEdge = NSMaxX(_expandRect);
      }
      const CGFloat modeLeft = rightEdge + gap;
      _modeRect = NSMakeRect(modeLeft, controlTop, modeW, chipH);
      rightEdge = NSMaxX(_modeRect);
    }
  } else {
    _modeRect = NSMakeRect(padding, padding, modeW, chipH);
    rightEdge = NSMaxX(_modeRect);
  }

  _contentSize = NSMakeSize(expandedGrid ? gridRight + padding : MAX(48, rightEdge + padding),
                            expandedGrid ? NSMaxY(_modeRect) + padding : chipH + 2 * padding);
}

- (void)drawChevronInRect:(NSRect)rect expanded:(BOOL)expanded color:(NSColor *)color {
  // Locked anchor: collapsed chevron sits at the lower-left of its own cell.
  const CGFloat cx = expanded ? NSMidX(rect) : NSMinX(rect) + kDisclosureInsetX;
  const CGFloat cy = expanded ? NSMidY(rect) : NSMaxY(rect) - kDisclosureInsetBottom;
  NSBezierPath *path = [NSBezierPath bezierPath];
  path.lineWidth = 1;
  path.lineCapStyle = NSLineCapStyleRound;
  path.lineJoinStyle = NSLineJoinStyleRound;
  if (expanded) {
    [path moveToPoint:NSMakePoint(cx - 5, cy + 3)];
    [path lineToPoint:NSMakePoint(cx, cy - 3)];
    [path lineToPoint:NSMakePoint(cx + 5, cy + 3)];
  } else {
    [path moveToPoint:NSMakePoint(cx - 5, cy - 3)];
    [path lineToPoint:NSMakePoint(cx, cy + 3)];
    [path lineToPoint:NSMakePoint(cx + 5, cy - 3)];
  }
  [color setStroke];
  [path stroke];
}

- (void)drawText:(NSString *)text inRect:(NSRect)rect color:(NSColor *)color font:(NSFont *)font
       alignment:(NSTextAlignment)alignment allowEllipsis:(BOOL)allowEllipsis {
  NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
  style.alignment = alignment;
  style.lineBreakMode = allowEllipsis ? NSLineBreakByTruncatingTail : NSLineBreakByClipping;
  NSDictionary *attrs = @{NSFontAttributeName: font,
                          NSForegroundColorAttributeName: color,
                          NSParagraphStyleAttributeName: style};
  const NSSize size = [text sizeWithAttributes:attrs];
  const CGFloat y = NSMinY(rect) + (NSHeight(rect) - size.height) / 2; // single line, vertically centered
  [text drawWithRect:NSMakeRect(NSMinX(rect), y, NSWidth(rect), size.height)
             options:NSStringDrawingUsesLineFragmentOrigin | (allowEllipsis ? NSStringDrawingTruncatesLastVisibleLine : 0)
          attributes:attrs];
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  const NSInteger theme = _theme; // 0 蓝夜, 1 暖白, 2 石墨
  NSColor *background = theme == 1 ? GYHex(0xFCFCFB) : GYHex(kGYInk);
  NSColor *border = theme == 0 ? GYHex(0x31353D) : theme == 1 ? GYHex(0xE1E5EB) : GYHex(0x343943);
  NSColor *muted = theme == 0 ? GYHex(0x979DA9) : theme == 1 ? GYHex(0x606C7A) : GYHex(0x949EAE);
  NSColor *text = theme == 1 ? GYHex(kGYInk) : GYHex(0xF6F8FC);
  NSColor *selectedBg = theme == 2 ? GYHex(0x485160) : GYHex(kGYBlue);
  NSColor *selectedText = NSColor.whiteColor;

  const NSRect bounds = self.bounds;
  [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:9 yRadius:9] setClip];
  [background setFill];
  NSRectFill(bounds);
  NSBezierPath *frame = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 0.5, 0.5) xRadius:9 yRadius:9];
  frame.lineWidth = 1;
  [border setStroke];
  [frame stroke];

  [self drawText:self.modeLabel inRect:_modeRect color:GYHex(kGYBlue) font:self.statusFont
       alignment:NSTextAlignmentCenter allowEllipsis:YES];

  if (!_modePopup && !NSEqualRects(_expandRect, NSZeroRect)) {
    const CGFloat divider = NSMaxX(_expandRect) + 1;
    [border setFill];
    NSRectFill(NSMakeRect(divider, NSMinY(_expandRect) + 7, 1, NSHeight(_expandRect) - 14));
  }

  for (NSUInteger i = 0; i < _candidateRects.count; ++i) {
    const NSUInteger index = _pageStart + i;
    const NSRect chip = _candidateRects[i].rectValue;
    const BOOL selected = index == _selected;
    if (selected) {
      [selectedBg setFill];
      [[NSBezierPath bezierPathWithRoundedRect:chip xRadius:6 yRadius:6] fill];
    }
    const BOOL hasShortcut = !_expanded || i < kCandidatesPerPage;
    [self drawText:hasShortcut ? [NSString stringWithFormat:@"%lu", (unsigned long)(i + 1)] : @""
            inRect:NSMakeRect(NSMinX(chip) + 6, NSMinY(chip), 13, NSHeight(chip))
             color:selected ? selectedText : muted font:self.keyFont
         alignment:NSTextAlignmentCenter allowEllipsis:NO];
    NSString *word = _candidates[index];
    // Candidate text is an input decision, not decorative copy — matching
    // Windows, ellipsis is only ever the honest last resort for a row that
    // physically overflows its (already width-negotiated) cell, never a
    // decision made from word length alone.
    [self drawText:word
            inRect:NSMakeRect(NSMinX(chip) + 21, NSMinY(chip), NSWidth(chip) - 21 - 5, NSHeight(chip))
             color:selected ? selectedText : text font:self.candidateFont
         alignment:NSTextAlignmentLeft allowEllipsis:YES];
  }

  if (!_modePopup && !NSEqualRects(_nextRect, NSZeroRect)) {
    const NSUInteger pageSize = _expanded ? kExpandedColumns * kExpandedMaxRows : kCandidatesPerPage;
    const BOOL canPrev = _pageStart > 0;
    const BOOL canNext = _pageStart + pageSize < _candidates.count;
    const NSUInteger page = _pageStart / pageSize + 1;
    const NSUInteger pages = (_candidates.count + pageSize - 1) / pageSize;
    [self drawText:@"↑" inRect:_prevRect color:canPrev ? GYHex(kGYBlue) : muted font:self.pagerFont
         alignment:NSTextAlignmentCenter allowEllipsis:NO];
    [self drawText:[NSString stringWithFormat:@"%lu / %lu", (unsigned long)page, (unsigned long)pages]
            inRect:_indicatorRect color:muted font:self.keyFont
         alignment:NSTextAlignmentCenter allowEllipsis:NO];
    [self drawText:@"↓" inRect:_nextRect color:canNext ? GYHex(kGYBlue) : muted font:self.pagerFont
         alignment:NSTextAlignmentCenter allowEllipsis:NO];
  }
  if (!_modePopup && !NSEqualRects(_expandRect, NSZeroRect)) {
    [self drawChevronInRect:_expandRect expanded:_expanded color:GYHex(kGYDisclosure)];
  }
}

- (void)resetCursorRects {
  if (_modePopup) return;
  NSCursor *hand = NSCursor.pointingHandCursor;
  for (NSValue *value in _candidateRects) [self addCursorRect:value.rectValue cursor:hand];
  [self addCursorRect:_modeRect cursor:hand];
  if (!NSEqualRects(_expandRect, NSZeroRect)) [self addCursorRect:_expandRect cursor:hand];
  if (!NSEqualRects(_prevRect, NSZeroRect)) [self addCursorRect:_prevRect cursor:hand];
  if (!NSEqualRects(_nextRect, NSZeroRect)) [self addCursorRect:_nextRect cursor:hand];
}

- (void)mouseUp:(NSEvent *)event {
  if (_modePopup) return;
  const NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  if (NSPointInRect(point, _modeRect)) { if (_settings) _settings(); return; }
  if (!NSEqualRects(_prevRect, NSZeroRect) && NSPointInRect(point, _prevRect)) { if (_page) _page(-1); return; }
  if (!NSEqualRects(_nextRect, NSZeroRect) && NSPointInRect(point, _nextRect)) { if (_page) _page(1); return; }
  if (!NSEqualRects(_expandRect, NSZeroRect) && NSPointInRect(point, _expandRect)) {
    if (_disclosure) _disclosure(!_expanded);
    return;
  }
  for (NSUInteger i = 0; i < _candidateRects.count; ++i) {
    if (NSPointInRect(point, _candidateRects[i].rectValue)) {
      if (_choose) _choose(_pageStart + i);
      return;
    }
  }
}

@end

@implementation GYCandidateWindow {
  NSPanel *_panel;
  GYCandidateView *_view;
  NSTimer *_modeTimer;
  NSPoint _lastStableAnchor;
  CGFloat _lastStableLineHeight;
  BOOL _hasStableAnchor;
  void (^_choose)(NSUInteger);
  void (^_disclosure)(BOOL);
  void (^_page)(NSInteger);
  void (^_settings)(void);
}

- (instancetype)initWithChooseHandler:(void (^)(NSUInteger))choose
                   disclosureHandler:(void (^)(BOOL))disclosure
                         pageHandler:(void (^)(NSInteger))page
                     settingsHandler:(void (^)(void))settings {
  self = [super init];
  if (!self) return nil;
  _choose = [choose copy];
  _disclosure = [disclosure copy];
  _page = [page copy];
  _settings = [settings copy];

  _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 48, 32)
                                      styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                        backing:NSBackingStoreBuffered
                                          defer:NO];
  _panel.level = NSStatusWindowLevel;
  _panel.opaque = NO;
  _panel.backgroundColor = NSColor.clearColor;
  _panel.hasShadow = YES; // extremely weak platform shadow; no glow
  _panel.hidesOnDeactivate = NO;
  _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                              NSWindowCollectionBehaviorFullScreenAuxiliary |
                              NSWindowCollectionBehaviorIgnoresCycle;

  _view = [[GYCandidateView alloc] initWithFrame:NSMakeRect(0, 0, 48, 32)];
  __weak typeof(self) weakSelf = self;
  _view->_choose = ^(NSUInteger index) { [weakSelf handleChoose:index]; };
  _view->_disclosure = ^(BOOL expanded) { [weakSelf handleDisclosure:expanded]; };
  _view->_page = ^(NSInteger direction) { [weakSelf handlePage:direction]; };
  _view->_settings = ^{ [weakSelf handleSettings]; };
  _panel.contentView = _view;
  return self;
}

- (void)handleChoose:(NSUInteger)index { if (_choose) _choose(index); }
- (void)handleDisclosure:(BOOL)expanded { if (_disclosure) _disclosure(expanded); }
- (void)handlePage:(NSInteger)direction { if (_page) _page(direction); }
- (void)handleSettings { if (_settings) _settings(); }

- (NSScreen *)screenForCaret:(NSRect)caret {
  const NSPoint caretPoint = NSMakePoint(NSMidX(caret), NSMidY(caret));
  NSScreen *best = nil;
  CGFloat bestArea = -1;
  for (NSScreen *screen in NSScreen.screens) {
    if (NSPointInRect(caretPoint, screen.frame)) return screen;
    const NSRect intersection = NSIntersectionRect(screen.frame, caret);
    const CGFloat area = NSWidth(intersection) * NSHeight(intersection);
    if (area > bestArea) { bestArea = area; best = screen; }
  }
  return best ?: NSScreen.mainScreen;
}
- (void)showAtCaret:(NSRect)caret
         candidates:(NSArray<NSString *> *)candidates
           selected:(NSUInteger)selected
          pageStart:(NSUInteger)pageStart
           expanded:(BOOL)expanded
          inputMode:(NSInteger)inputMode {
  [_modeTimer invalidate];
  _modeTimer = nil;
  if (candidates.count == 0) { [self hide]; return; }

  _view->_candidates = candidates;
  _view->_selected = MIN(selected, candidates.count - 1);
  _view->_expanded = expanded;
  _view->_inputMode = inputMode;
  _view->_modePopup = NO;
  _view->_theme = MAX(0, MIN(2, GYSettingsStore.sharedStore.candidateTheme));
  _view->_candidateSize = MAX(13, MIN(17, GYSettingsStore.sharedStore.candidateFontSize));

  const NSUInteger pageSize = expanded ? kExpandedColumns * kExpandedMaxRows : kCandidatesPerPage;
  const NSUInteger lastPage = ((candidates.count - 1) / pageSize) * pageSize;
  pageStart = MIN(pageStart, lastPage);
  if (_view->_selected < pageStart || _view->_selected >= pageStart + pageSize) {
    pageStart = _view->_selected / pageSize * pageSize;
  }
  _view->_pageStart = pageStart;

  [self showInternalAtCaret:caret];
}

- (void)showModeAtCaret:(NSRect)caret inputMode:(NSInteger)inputMode {
  _view->_candidates = @[];
  _view->_selected = 0;
  _view->_pageStart = 0;
  _view->_expanded = NO;
  _view->_inputMode = inputMode;
  _view->_modePopup = YES;
  _view->_theme = MAX(0, MIN(2, GYSettingsStore.sharedStore.candidateTheme));
  _view->_candidateSize = MAX(13, MIN(17, GYSettingsStore.sharedStore.candidateFontSize));
  [self showInternalAtCaret:caret];
  [_modeTimer invalidate];
  _modeTimer = [NSTimer scheduledTimerWithTimeInterval:0.7 target:self selector:@selector(hide) userInfo:nil repeats:NO];
}

- (void)showInternalAtCaret:(NSRect)caret {
  const CGFloat lineHeight = MAX(1, NSHeight(caret));
  if (!_hasStableAnchor) {
    _lastStableAnchor = caret.origin;
    _lastStableLineHeight = lineHeight;
    _hasStableAnchor = YES;
  } else {
    const CGFloat horizontalDelta = fabs(NSMinX(caret) - _lastStableAnchor.x);
    const CGFloat verticalDelta = fabs(NSMinY(caret) - _lastStableAnchor.y);
    const CGFloat verticalLimit = MAX(18, _lastStableLineHeight * 1.5);
    if (horizontalDelta > 96 || verticalDelta > verticalLimit) {
      caret.origin = _lastStableAnchor;
    } else {
      _lastStableAnchor = caret.origin;
      _lastStableLineHeight = lineHeight;
    }
  }

  NSScreen *screen = [self screenForCaret:caret];
  const NSRect visible = screen.visibleFrame;
  // Product rule: fixed 5×5 expanded grid; screen size caps width, never columns.
  const CGFloat logicalWidth = NSWidth(screen.frame);
  const CGFloat widthCap = logicalWidth <= 1600 ? 620 : 720;
  const CGFloat available = MAX(180, MIN(620, MIN(widthCap, NSWidth(visible) - 20)));
  [_view layoutForAvailableWidth:available];

  const NSSize size = _view->_contentSize;
  CGFloat x = MAX(NSMinX(visible), MIN(NSMinX(caret), NSMaxX(visible) - size.width));
  // Below the caret; flip above when there is no room underneath.
  CGFloat y = NSMinY(caret) - 5 - size.height;
  if (y < NSMinY(visible) && NSMaxY(caret) + 5 + size.height <= NSMaxY(visible)) {
    y = NSMaxY(caret) + 5;
  }
  y = MAX(NSMinY(visible), MIN(y, NSMaxY(visible) - size.height));

  [_view setFrameSize:size];
  [_panel setFrame:NSMakeRect(x, y, size.width, size.height) display:NO];
  [_view setNeedsDisplay:YES];
  [_panel orderFront:nil];
}

- (void)hide {
  _hasStableAnchor = NO;
  [_modeTimer invalidate];
  _modeTimer = nil;
  [_panel orderOut:nil];
}

- (void)dealloc {
  [_modeTimer invalidate];
}

@end
