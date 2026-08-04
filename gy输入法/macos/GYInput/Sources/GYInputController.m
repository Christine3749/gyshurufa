#import "GYInputController.h"
#import "GYRimeBridge.h"
#import "GYInputMode.h"
#import "GYSettingsStore.h"
#import "GYPreferencesController.h"
#import "GYCandidateWindow.h"
#import <Carbon/Carbon.h>

// WINDOWS-DESIGN.md §4/§5: collapsed strip shows 5, expanded grid is 5×5,
// the pool holds up to 75 candidates (3 pages of 25), PageUp/Down flip 25.
static const NSUInteger kCollapsedPageSize = 5;
static const NSUInteger kExpandedPageSize = 25;
static const NSUInteger kCandidateFetchLimit = 75;

@implementation GYInputController {
  GYRimeBridge *_engine;
  GYCandidateWindow *_candidateWindow;
  NSArray<NSString *> *_candidates;
  NSString *_composition;
  GYInputMode _mode;
  NSUInteger _selected;
  NSUInteger _pageStart;
  BOOL _expanded;
  BOOL _shiftAwaitingSoleRelease;
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
  _mode = GYSettingsStore.sharedStore.inputMode;
  [_engine setInputMode:_mode];
  return self;
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
- (void)refetchCandidatesForCode:(NSString *)code {
  NSArray<NSString *> *rime = [_engine candidatesForCode:code];
  rime = rime.count != 0 ? [_engine candidatesUpToCount:kCandidateFetchLimit] : @[];
  _candidates = [GYSettingsStore.sharedStore candidatesByAddingCustomPhrases:rime forCode:code];
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

// PageUp/PageDown flip a whole 25-candidate page in both strip and grid.
- (void)pageCandidateWindow:(NSInteger)direction client:(id)client {
  if (direction > 0) {
    if (_pageStart + kExpandedPageSize < _candidates.count) {
      _pageStart += kExpandedPageSize;
      _selected = _pageStart;
    } else if ([_engine pageDown]) {
      _candidates = [GYSettingsStore.sharedStore
          candidatesByAddingCustomPhrases:[_engine candidatesUpToCount:kCandidateFetchLimit]
                                  forCode:_composition];
      _pageStart = 0;
      _selected = 0;
    }
  } else {
    if (_pageStart > 0) {
      _pageStart -= kExpandedPageSize;
      _selected = _pageStart;
    } else if ([_engine pageUp]) {
      _candidates = [GYSettingsStore.sharedStore
          candidatesByAddingCustomPhrases:[_engine candidatesUpToCount:kCandidateFetchLimit]
                                  forCode:_composition];
      _pageStart = _candidates.count != 0 ? ((_candidates.count - 1) / kExpandedPageSize) * kExpandedPageSize : 0;
      _selected = _pageStart;
    }
  }
  [self updateCandidateWindowForClient:client];
}

// Grid navigation (expanded state). All movements clamp to real candidates;
// the last, possibly short, row never invents a cell.
- (void)moveSelectionHorizontally:(NSInteger)delta client:(id)client {
  const NSInteger next = (NSInteger)_selected + delta;
  if (next >= 0 && next < (NSInteger)_candidates.count) {
    _selected = (NSUInteger)next;
    if (_selected < _pageStart) _pageStart -= kExpandedPageSize;
    if (_selected >= _pageStart + kExpandedPageSize) _pageStart += kExpandedPageSize;
  }
  [self updateCandidateWindowForClient:client];
}

- (void)moveSelectionDownWithClient:(id)client {
  const NSUInteger count = _candidates.count;
  const NSUInteger next = _selected + kCollapsedPageSize;
  if (next < count) {
    _selected = next;
    if (_selected >= _pageStart + kExpandedPageSize) _pageStart += kExpandedPageSize;
  } else if (_pageStart + kExpandedPageSize < count) {
    // Page bottom: cross to the next page in the same column.
    const NSUInteger column = (_selected - _pageStart) % kCollapsedPageSize;
    const NSUInteger target = _pageStart + kExpandedPageSize + column;
    if (target < count) {
      _selected = target;
      _pageStart += kExpandedPageSize;
    }
  }
  [self updateCandidateWindowForClient:client];
}

- (void)moveSelectionUpWithClient:(id)client {
  if (_selected - _pageStart >= kCollapsedPageSize) {
    _selected -= kCollapsedPageSize;
  } else if (_pageStart > 0) {
    _pageStart -= kExpandedPageSize;
    _selected -= kCollapsedPageSize;
  } else {
    // First page, first row: ↑ collapses back to the single-row strip.
    _expanded = NO;
    _pageStart = 0;
    _selected = 0;
  }
  [self updateCandidateWindowForClient:client];
}

// Commits the displayed candidate at index, then refreshes any composition
// remainder Rime kept (sentence-style partial commits). A custom phrase at
// index 0 bypasses Rime, so the engine composition is cleared instead.
- (void)commitCandidateSelectionAtIndex:(NSUInteger)index
                                 suffix:(nullable NSString *)suffix
                                 client:(id)client {
  if (index >= _candidates.count || client == nil) return;
  NSArray<NSString *> *phrases = GYSettingsStore.sharedStore.customPhrases[_composition.lowercaseString];
  NSString *phrase = phrases.firstObject;
  NSArray<NSString *> *rimeCandidates = [_engine currentCandidates];
  BOOL insertedCustomPhrase = phrase.length != 0 &&
      [_candidates.firstObject isEqualToString:phrase] &&
      ![rimeCandidates containsObject:phrase];
  NSString *tail = suffix ?: @"";
  if (insertedCustomPhrase && index == 0) {
    [_engine clearComposition];
    [self commitText:[phrase stringByAppendingString:tail]];
    return;
  }
  NSUInteger rimeIndex = insertedCustomPhrase ? index - 1 : index;
  NSString *commit = [_engine commitCandidateAtAbsoluteIndex:rimeIndex];
  if (commit == nil) return;
  [client insertText:[commit stringByAppendingString:tail]
    replacementRange:NSMakeRange(NSNotFound, 0)];
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
  NSArray<NSNumber *> *modes = @[@(GYInputModeSimplified), @(GYInputModeTraditional), @(GYInputModeEnglish)];
  for (NSNumber *value in modes) {
    GYInputMode mode = (GYInputMode)value.integerValue;
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:GYInputModeTitle(mode) action:@selector(selectMode:) keyEquivalent:@""];
    item.target = self;
    item.tag = mode;
    item.state = _mode == mode ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:item];
  }
  [menu addItem:NSMenuItem.separatorItem];
  NSMenuItem *preferences = [[NSMenuItem alloc] initWithTitle:@"设置…" action:@selector(showPreferences:) keyEquivalent:@","];
  preferences.target = self;
  preferences.keyEquivalentModifierMask = NSEventModifierFlagCommand;
  NSMenuItem *status = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"GY Input · %@", GYInputModeTitle(_mode)] action:nil keyEquivalent:@""];
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
    // Collapsed commits the strip's first candidate; expanded the highlight.
    [self commitCandidateSelectionAtIndex:_expanded ? _selected : _pageStart
                                   suffix:nil client:client];
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
      if (_candidates.count > kCollapsedPageSize) _expanded = YES;
      [self updateCandidateWindowForClient:client];
    } else {
      [self moveSelectionDownWithClient:client];
    }
    return YES;
  }
  if (keyCode == kVK_UpArrow) {
    if (_expanded && _candidates.count != 0) {
      [self moveSelectionUpWithClient:client];
      return YES;
    }
    return NO; // collapsed: pass through
  }
  if (keyCode == kVK_LeftArrow || keyCode == kVK_RightArrow) {
    if (_expanded && _candidates.count != 0) {
      [self moveSelectionHorizontally:keyCode == kVK_LeftArrow ? -1 : 1 client:client];
      return YES;
    }
    return NO; // collapsed: pass through
  }

  if (keyCode >= kVK_ANSI_1 && keyCode <= kVK_ANSI_5 && _candidates.count != 0) {
    const NSUInteger digit = (NSUInteger)(keyCode - kVK_ANSI_1);
    if (_expanded) {
      // Row of the highlight, column N; a short last row must not misselect.
      const NSUInteger rowStart = _pageStart + ((_selected - _pageStart) / kCollapsedPageSize) * kCollapsedPageSize;
      const NSUInteger rowCount = MIN(kCollapsedPageSize, _candidates.count - rowStart);
      if (digit < rowCount) {
        [self commitCandidateSelectionAtIndex:rowStart + digit suffix:nil client:client];
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
    NSDictionary<NSString *, NSString *> *punctuation = @{@",": @"，", @".": @"。", @"?": @"？", @"!": @"！", @";": @"；", @":": @"："};
    NSString *converted = punctuation[string];
    if (converted != nil) {
      if (_composition.length == 0) {
        [self commitText:converted];
      } else if (_candidates.count != 0) {
        // Mid-composition: commit the top candidate plus the punctuation, and
        // keep any Rime remainder alive via the selection path.
        [self commitCandidateSelectionAtIndex:0 suffix:converted client:client];
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
