#import "GYInputController.h"
#import "GYRimeBridge.h"
#import "GYInputMode.h"
#import "GYSettingsStore.h"
#import "GYPreferencesController.h"
#import "GYClipboardHistory.h"
#import "GYKeepSync.h"
#import "GYCandidateWindow.h"
#import "GYCandidateGovernance.h"
#import "GYCandidateGridMath.h"
#import "GYPunctuationPolicy.h"
#import <Carbon/Carbon.h>

// WINDOWS-DESIGN.md §4/§5: collapsed strip shows 5, expanded grid is 5×5,
// the pool holds up to 75 candidates (3 pages of 25), PageUp/Down flip 25.
static const NSUInteger kCollapsedPageSize = kGYCollapsedPageSize;
static const NSUInteger kCandidateFetchLimit = 75;


// Menu actions must target a long-lived object: IMK input controllers are
// per-client-session and may be deallocated while the system input menu is
// still showing items that point at them, which makes clicks silently die.
@interface GYMenuActionTarget : NSObject
+ (instancetype)sharedTarget;
@end

// The system Input Menu is served by GYMenuActionTarget, a singleton wholly
// decoupled from any specific GYInputController instance. Writing
// GYSettingsStore alone leaves the *currently active* controller instance —
// its mode badge, engine mode and candidate window — unchanged until the
// next composition-free keystroke happens to poll the store. That reads to
// the user as "clicking 简/繁/EN does nothing." Broadcasting this
// notification lets every live instance apply the change immediately.
static NSNotificationName const GYInputModeMenuDidSelectNotification = @"GYInputModeMenuDidSelectNotification";

@implementation GYMenuActionTarget
+ (instancetype)sharedTarget {
  static GYMenuActionTarget *target;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ target = [[GYMenuActionTarget alloc] init]; });
  return target;
}
- (void)selectMode:(NSMenuItem *)sender {
  GYInputMode mode = (GYInputMode)sender.tag;
  GYSettingsStore.sharedStore.inputMode = mode;
  if (GYInputModeIsChinese(mode)) GYSettingsStore.sharedStore.lastChineseMode = mode;
  [NSNotificationCenter.defaultCenter postNotificationName:GYInputModeMenuDidSelectNotification object:nil];
}
- (void)showPreferences:(id)sender {
  (void)sender;
  [GYPreferencesController.sharedController show];
}
@end

@implementation GYInputController {
  GYRimeBridge *_engine;
  GYCandidateWindow *_candidateWindow;
  NSArray<NSString *> *_candidates;
  NSArray<GYCandidateSelection *> *_candidateSelections;
  NSString *_composition;
  GYInputMode _mode;
  NSUInteger _selected;
  NSUInteger _pageStart;
  BOOL _expanded;
  BOOL _shiftAwaitingSoleRelease;
  BOOL _singleQuoteOpen;
  BOOL _doubleQuoteOpen;
}

- (instancetype)initWithServer:(IMKServer *)server delegate:(id)delegate client:(id)client {
  self = [super initWithServer:server delegate:delegate client:client];
  if (!self) return nil;

  NSURL *shared = [NSBundle.mainBundle URLForResource:@"rime-data" withExtension:nil];
  NSURL *support = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                          inDomains:NSUserDomainMask] firstObject];
  NSURL *user = [[support URLByAppendingPathComponent:@"GYInput" isDirectory:YES]
                           URLByAppendingPathComponent:@"rime" isDirectory:YES];
  [NSFileManager.defaultManager createDirectoryAtURL:user withIntermediateDirectories:YES attributes:nil error:nil];
  _engine = [[GYRimeBridge alloc] initWithSharedDataURL:shared userDataURL:user];
  [[GYClipboardHistory sharedHistory] startCapture];
  // Keep 同步是后台服务：只在自己的串行队列上跑网络，
  // 不参与组合、候选或 Rime 路径。两者都幂等，重复调用无副作用。
  [[GYKeepSync sharedSync] start];

  __weak typeof(self) weakSelf = self;
  _candidateWindow = [[GYCandidateWindow alloc]
      initWithChooseHandler:^(NSUInteger index) {
        [weakSelf commitCandidateSelectionAtIndex:index suffix:nil client:weakSelf.client];
      }
      disclosureHandler:^(BOOL expanded) {
        typeof(self) strongSelf = weakSelf;
        strongSelf->_expanded = expanded;
        if (!expanded) {
          strongSelf->_pageStart = 0;
          strongSelf->_selected = 0;
        }
        [strongSelf updateCandidateWindowForClient:strongSelf.client];
      }
      pageHandler:^(NSInteger direction) {
        [weakSelf pageCandidateWindow:direction client:weakSelf.client];
      }
      settingsHandler:^{
        [weakSelf showPreferences:nil];
      }];

  _composition = @"";
  _candidates = @[];
  _selected = 0;
  _pageStart = 0;
  _expanded = NO;
  _shiftAwaitingSoleRelease = NO;
  _singleQuoteOpen = YES;
  _doubleQuoteOpen = YES;
  _mode = GYSettingsStore.sharedStore.inputMode;
  [_engine setInputMode:_mode];
  [NSNotificationCenter.defaultCenter addObserver:self
                                          selector:@selector(handleMenuModeChange:)
                                              name:GYInputModeMenuDidSelectNotification
                                            object:nil];
  return self;
}

- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self name:GYInputModeMenuDidSelectNotification object:nil];
}

// The system Input Menu (GYMenuActionTarget, a singleton) broadcasts this so
// every live controller instance — not just whichever one happens to see the
// next keystroke — applies the switch immediately: mode badge, engine mode
// and candidate window all update right away instead of only on next type.
- (void)handleMenuModeChange:(NSNotification *)notification {
  (void)notification;
  [self applyInputMode:GYSettingsStore.sharedStore.inputMode];
}

- (void)applyInputMode:(GYInputMode)mode {
  if (_mode == mode) return;
  // Switching away mid-composition cancels the preedit; nothing is committed.
  [self cancelComposition];
  _mode = mode;
  GYSettingsStore.sharedStore.inputMode = mode;
  if (GYInputModeIsChinese(mode)) GYSettingsStore.sharedStore.lastChineseMode = mode;
  [_engine setInputMode:mode];
  id client = self.client;
  if (client != nil) {
    [_candidateWindow showModeAtCaret:[self caretRectForClient:client] inputMode:(NSInteger)_mode];
  }
}

- (void)selectMode:(NSMenuItem *)sender {
  [self applyInputMode:(GYInputMode)sender.tag];
}
- (void)showPreferences:(id)sender {
  (void)sender;
  [GYPreferencesController.sharedController show];
}

// Sole Shift press-release cycles 中⇄EN, remembering the last Chinese mode.
- (void)toggleChineseEnglish {
  [self applyInputMode:_mode == GYInputModeEnglish
      ? GYSettingsStore.sharedStore.lastChineseMode
      : GYInputModeEnglish];
}

// Chinese punctuation set, matching Windows PunctuationPolicy.h exactly:
// shift-combo book titles/brackets/dun-comma plus a stateful smart-quote
// toggle for the ' and " keys.
- (nullable NSString *)chinesePunctuationForString:(NSString *)string {
  return GYChinesePunctuationLookup(string, &_singleQuoteOpen, &_doubleQuoteOpen);
}

- (NSRect)caretRectForClient:(id)client {
  NSRect rect = NSZeroRect;
  @try {
    if ([client respondsToSelector:@selector(attributesForCharacterIndex:lineHeightRectangle:)]) {
      [client attributesForCharacterIndex:0 lineHeightRectangle:&rect];
    }
  } @catch (__unused NSException *exception) {
    rect = NSZeroRect;
  }
  if (rect.size.height <= 0) {
    const NSPoint mouse = NSEvent.mouseLocation;
    rect = NSMakeRect(mouse.x, mouse.y - 18, 4, 18);
  }
  return rect;
}

// Fetches the governed 75-candidate pool and merges per-code custom phrases
// at the front, like the Windows pipeline.
// Keep the candidate window presentation as plain strings while retaining the
// exact selection owner. Local phrases never enter Rime; Rime entries retain
// their filtered display index so GYRimeBridge can translate it to raw Rime.
- (void)setCandidateSelectionsFromRimeCandidates:(NSArray<NSString *> *)rimeCandidates
                                          forCode:(NSString *)code {
  _candidateSelections = [GYCandidateGovernance
      selectionsForRimeCandidates:rimeCandidates
                     customPhrases:[GYSettingsStore.sharedStore customPhrasesForCode:code]];
  NSMutableArray<NSString *> *texts = [NSMutableArray arrayWithCapacity:_candidateSelections.count];
  for (GYCandidateSelection *selection in _candidateSelections) {
    [texts addObject:selection.text];
  }
  _candidates = texts.copy;
}

// Fetches the governed 75-candidate pool and merges per-code custom phrases
// at the front, like the Windows pipeline.
- (void)refetchCandidatesForCode:(NSString *)code {
  NSArray<NSString *> *rime = [_engine candidatesForCode:code];
  rime = rime.count != 0 ? [_engine candidatesUpToCount:kCandidateFetchLimit] : @[];
  [self setCandidateSelectionsFromRimeCandidates:rime forCode:code];
  _selected = 0;
  _pageStart = 0;
}

- (void)updateCandidateWindowForClient:(id)client {
  if (client == nil) return;
  [_candidateWindow showAtCaret:[self caretRectForClient:client]
                     candidates:_candidates
                       selected:_selected
                      pageStart:_pageStart
                       expanded:_expanded
                      inputMode:(NSInteger)_mode];
}

// PageUp/PageDown flip a whole 25-candidate page in the grid, but only a
// 5-candidate row in the collapsed strip — matching Windows
// PageSizeForCurrentView(). This is a pure clamp within the already-fetched
// pool (byte-for-byte ported from GyIme.cpp's MovePage()). It must NOT
// re-query the Rime engine at the pool boundary: candidatesUpToCount: already
// walked Rime's own deep pages once to build the full ≤75-candidate pool, so
// calling engine pageUp/pageDown here would advance Rime's session page
// out from under that stable pool and could re-fetch a different, shifted
// candidate set — a real product-contract violation Windows has no
// equivalent of.
- (void)pageCandidateWindow:(NSInteger)direction client:(id)client {
  const NSUInteger pageSize = GYPageSizeForState(_expanded);
  const GYPageMoveResult result = GYMovePageTransition(_pageStart, direction, pageSize, _candidates.count);
  _pageStart = result.pageStart;
  _selected = result.selected;
  [self updateCandidateWindowForClient:client];
}

// Collapsed strip left/right: move the highlighted candidate by one with
// wraparound over the whole fetched pool, matching Windows MoveSelection().
- (void)moveSelectionCollapsed:(NSInteger)delta client:(id)client {
  if (_candidates.count == 0) return;
  _selected = GYMoveCollapsedSelection(_selected, delta, _candidates.count);
  _pageStart = (_selected / kCollapsedPageSize) * kCollapsedPageSize;
  [self updateCandidateWindowForClient:client];
}

// Grid navigation (expanded state), byte-for-byte ported from
// CandidateLayout.h's MoveExpandedLeft/Right/Down/Up so short final rows,
// page-bottom column crossing and clamping match Windows exactly.
- (void)moveSelectionHorizontally:(NSInteger)delta client:(id)client {
  _selected = delta < 0
      ? GYMoveExpandedLeft(_selected, _pageStart, _candidates.count)
      : GYMoveExpandedRight(_selected, _pageStart, _candidates.count);
  [self updateCandidateWindowForClient:client];
}

- (void)moveSelectionDownWithClient:(id)client {
  const GYCandidateNavResult result = GYExpandedDownTransition(_selected, _pageStart, _candidates.count);
  _selected = result.selected;
  _pageStart = result.pageStart;
  [self updateCandidateWindowForClient:client];
}

- (void)moveSelectionUpWithClient:(id)client {
  const GYCandidateNavResult result = GYExpandedUpTransition(_selected, _pageStart, _candidates.count);
  _selected = result.selected;
  _pageStart = result.pageStart;
  _expanded = result.expanded;
  [self updateCandidateWindowForClient:client];
}

// Commits the displayed candidate at index, then refreshes any composition
// remainder Rime kept (sentence-style partial commits). A custom phrase at
// index 0 bypasses Rime, so the engine composition is cleared instead.
// Commits a governed selection. Local phrases bypass Rime; every Rime entry
// keeps the bridge display index even when local phrases were prepended.
- (void)commitCandidateSelectionAtIndex:(NSUInteger)index
                                 suffix:(nullable NSString *)suffix
                                 client:(id)client {
  if (index >= _candidateSelections.count || client == nil) return;
  GYCandidateSelection *selection = _candidateSelections[index];
  NSString *tail = suffix ?: @"";
  if (selection.localPhrase) {
    [_engine clearComposition];
    _composition = @"";
    _candidates = @[];
    _candidateSelections = @[];
    [_candidateWindow hide];
    [self commitText:[selection.text stringByAppendingString:tail]];
    return;
  }
  NSString *selected = [_engine commitCandidateAtAbsoluteIndex:selection.rimeDisplayIndex];
  if (selected.length == 0) return;
  [self commitText:[selected stringByAppendingString:tail]];
  [self refreshRemainderForClient:client];
}

// After a partial Rime commit, the session may still hold unconsumed pinyin
// (selecting 下一 from xiayigeban leaves yigeban). Keep it alive instead of
// dropping it; only reset when nothing remains.
- (void)refreshRemainderForClient:(id)client {
  NSString *rest = [_engine remainingCompositionInput];
  if (rest.length == 0) {
    _composition = @"";
    _candidates = @[];
    [_engine clearComposition];
    [_candidateWindow hide];
    return;
  }
  _composition = rest;
  [self refetchCandidatesForCode:_composition];
  [self updateMarkedTextForClient:client];
}

// IMK creates one controller per client session. When focus moves to another
// document or app, this session's candidate panel must not linger on screen.
- (void)deactivateServer:(id)sender {
  [self cancelComposition];
  [super deactivateServer:sender];
}

- (NSMenu *)menu {
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"输入法.网"];
  GYInputMode current = GYSettingsStore.sharedStore.inputMode;
  NSArray<NSNumber *> *modes = @[@(GYInputModeSimplified), @(GYInputModeTraditional), @(GYInputModeEnglish)];
  for (NSNumber *value in modes) {
    GYInputMode mode = (GYInputMode)value.integerValue;
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:GYInputModeTitle(mode) action:@selector(selectMode:) keyEquivalent:@""];
    item.target = GYMenuActionTarget.sharedTarget;
    item.tag = mode;
    item.state = current == mode ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:item];
  }
  [menu addItem:NSMenuItem.separatorItem];
  NSMenuItem *preferences = [[NSMenuItem alloc] initWithTitle:@"设置…" action:@selector(showPreferences:) keyEquivalent:@","];
  preferences.target = GYMenuActionTarget.sharedTarget;
  preferences.keyEquivalentModifierMask = NSEventModifierFlagCommand;
  [menu addItem:preferences];
  [menu addItem:NSMenuItem.separatorItem];
  NSMenuItem *status = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"GY Input · %@", GYInputModeTitle(current)] action:nil keyEquivalent:@""];
  status.enabled = NO;
  [menu addItem:status];
  return menu;
}

- (BOOL)inputText:(NSString *)string key:(NSInteger)keyCode modifiers:(NSUInteger)modifiers client:(id)client {
  const NSEventModifierFlags blockingModifiers = NSEventModifierFlagCommand |
      NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagFunction;

  // Sole-Shift mode toggle (press and release with no key in between).
  if (keyCode == kVK_Shift || keyCode == kVK_RightShift) {
    if ((modifiers & NSEventModifierFlagShift) != 0) {
      _shiftAwaitingSoleRelease = YES;
    } else if (_shiftAwaitingSoleRelease) {
      _shiftAwaitingSoleRelease = NO;
      [self toggleChineseEnglish];
    }
    return YES;
  }
  _shiftAwaitingSoleRelease = NO;

  if (_composition.length == 0 && _mode != GYSettingsStore.sharedStore.inputMode) {
    _mode = GYSettingsStore.sharedStore.inputMode;
    [_engine setInputMode:_mode];
  }

  // Arrow and paging keys arrive with the Function modifier flag set; they are
  // navigation for the candidate window, not modified shortcuts. Only genuine
  // Command/Control/Option chords are passed back to the application.
  const BOOL isNavigationKey = keyCode == kVK_DownArrow || keyCode == kVK_UpArrow ||
      keyCode == kVK_LeftArrow || keyCode == kVK_RightArrow ||
      keyCode == kVK_PageUp || keyCode == kVK_PageDown;
  if ((modifiers & blockingModifiers) != 0 &&
      (!isNavigationKey || (modifiers & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) != 0)) {
    return NO;
  }

  if (keyCode == kVK_Escape && _composition.length != 0) {
    [self cancelComposition];
    return YES;
  }
  if (keyCode == kVK_Return && _composition.length != 0) {
    // Collapsed: keep the raw pinyin as ASCII. Expanded: commit the highlight.
    if (_expanded && _candidates.count != 0) {
      [self commitCandidateSelectionAtIndex:_selected suffix:nil client:client];
    } else {
      [self commitText:_composition];
    }
    return YES;
  }

  if (keyCode == kVK_Delete && _composition.length != 0) {
    _composition = [_composition substringToIndex:_composition.length - 1];
    if (_composition.length == 0) {
      [self cancelComposition];
    } else {
      [self refetchCandidatesForCode:_composition];
      [self updateMarkedTextForClient:client];
    }
    return YES;
  }
  if (keyCode == kVK_Space && _candidates.count != 0) {
    // Space always commits the current highlight, matching Windows Space
    // behavior in both collapsed and expanded state.
    [self commitCandidateSelectionAtIndex:_selected suffix:nil client:client];
    return YES;
  }
  if (keyCode == kVK_PageUp && _composition.length != 0) {
    [self pageCandidateWindow:-1 client:client];
    return YES;
  }
  if (keyCode == kVK_PageDown && _composition.length != 0) {
    [self pageCandidateWindow:1 client:client];
    return YES;
  }

  // Locked interaction: keyboard ↓ enters the fixed 5×5 grid; inside the grid
  // the arrows move the highlight and cross page boundaries.
  if (keyCode == kVK_DownArrow && _candidates.count != 0) {
    if (!_expanded) {
      if (GYShouldEnterExpandedOnDown(_candidates.count)) _expanded = YES;
      [self updateCandidateWindowForClient:client];
    } else {
      [self moveSelectionDownWithClient:client];
    }
    return YES;
  }
  if (keyCode == kVK_UpArrow) {
    if (_candidates.count == 0) return NO;
    if (_expanded) {
      [self moveSelectionUpWithClient:client];
    } else {
      // Collapsed ↑ pages back by one row, matching Windows MovePage(-1, 5).
      [self pageCandidateWindow:-1 client:client];
    }
    return YES;
  }
  if (keyCode == kVK_LeftArrow || keyCode == kVK_RightArrow) {
    if (_candidates.count == 0) return NO;
    const NSInteger delta = keyCode == kVK_LeftArrow ? -1 : 1;
    if (_expanded) {
      [self moveSelectionHorizontally:delta client:client];
    } else {
      // Collapsed ←/→ move the highlight, matching Windows MoveSelection().
      [self moveSelectionCollapsed:delta client:client];
    }
    return YES;
  }

  const NSInteger digitOrNegative = GYDigitForKeyCode(keyCode);
  if (digitOrNegative >= 0 && _candidates.count != 0) {
    const NSUInteger digit = (NSUInteger)digitOrNegative;
    if (_expanded) {
      // Row of the highlight, column N; ported so a short last row can never
      // misselect a cell that doesn't exist, matching Windows exactly.
      const NSUInteger candidate = GYExpandedDigitCandidate(_selected, _pageStart, _candidates.count, digit + 1);
      if (candidate < _candidates.count) {
        [self commitCandidateSelectionAtIndex:candidate suffix:nil client:client];
      }
    } else {
      const NSUInteger index = _pageStart + digit;
      if (index < MIN(_candidates.count, _pageStart + kCollapsedPageSize)) {
        [self commitCandidateSelectionAtIndex:index suffix:nil client:client];
      }
    }
    return YES;
  }

  if (GYInputModeIsChinese(_mode)) {
    NSString *converted = [self chinesePunctuationForString:string];
    if (converted != nil) {
      if (_composition.length == 0) {
        [self commitText:converted];
      } else if (_candidates.count != 0) {
        // Mid-composition: commit the currently highlighted candidate plus
        // the punctuation, matching Windows (which always commits selected_
        // through the same InsertText path), and keep any Rime remainder
        // alive via the selection path.
        [self commitCandidateSelectionAtIndex:_selected suffix:converted client:client];
      } else {
        // No candidates: commit the raw pinyin followed by the punctuation.
        [self commitText:[_composition stringByAppendingString:converted]];
      }
      return YES;
    }
  }

  NSString *text = string.lowercaseString;
  if (!GYInputModeIsChinese(_mode) || text.length != 1 || [text rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location == NSNotFound) {
    return NO;
  }
  _composition = [_composition stringByAppendingString:text];
  [self refetchCandidatesForCode:_composition];
  [self updateMarkedTextForClient:client];
  return YES;
}

- (void)commitText:(NSString *)text {
  id client = self.client;
  if (client == nil) return;
  [client insertText:text replacementRange:NSMakeRange(NSNotFound, 0)];
  [_engine clearComposition];
  _composition = @"";
  _candidates = @[];
  _selected = 0;
  _pageStart = 0;
  _expanded = NO;
  [_candidateWindow hide];
}

- (void)updateMarkedTextForClient:(id)client {
  if (_composition.length == 0) return;
  NSAttributedString *marked = [[NSAttributedString alloc] initWithString:_composition];
  [client setMarkedText:marked
          selectionRange:NSMakeRange(_composition.length, 0)
        replacementRange:NSMakeRange(NSNotFound, 0)];
  [self updateCandidateWindowForClient:client];
}

- (void)cancelComposition {
  [_engine clearComposition];
  _composition = @"";
  _candidates = @[];
  _selected = 0;
  _pageStart = 0;
  _expanded = NO;
  [_candidateWindow hide];
  [super cancelComposition];
}

- (void)inputControllerWillClose {
  [self cancelComposition];
  [super inputControllerWillClose];
}

@end





