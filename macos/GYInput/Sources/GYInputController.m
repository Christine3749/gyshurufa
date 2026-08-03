#import "GYInputController.h"
#import "GYRimeBridge.h"
#import "GYCandidatePanel.h"
#import "GYInputMode.h"
#import "GYSettingsStore.h"
#import "GYPreferencesController.h"
#import "GYUpdateService.h"
#import <Carbon/Carbon.h>
#import <os/log.h>

static const unsigned short GYSelectionKeyCodes[] = {
    kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
};
static const NSUInteger GYCollapsedCandidatePageSize = 5;
static const NSUInteger GYExpandedCandidatePageSize = 25;
static const NSUInteger GYCandidateRowSize = 5;

static os_log_t GYInputEventLog(void) {
  static os_log_t log;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    log = os_log_create("wang.shurufa.inputmethod.GYInput", "keyboard");
  });
  return log;
}

static NSInteger GYCandidateIndexForKeyCode(unsigned short keyCode) {
  for (NSUInteger index = 0; index < sizeof(GYSelectionKeyCodes) / sizeof(GYSelectionKeyCodes[0]); ++index) {
    if (GYSelectionKeyCodes[index] == keyCode) return (NSInteger)index;
  }
  return NSNotFound;
}

static NSString *GYCompactModeTitle(GYInputMode mode) {
  switch (mode) {
    case GYInputModeTraditional: return @"繁";
    case GYInputModeEnglish: return @"EN";
    case GYInputModeSimplified: return @"简";
  }
}

// Some AppKit clients forward NSEvents to handleEvent:, while WebKit clients
// can use either of InputMethodKit's text callbacks.  Map the latter back to
// the same key-code path so every client has identical composition behavior.
static unsigned short GYKeyCodeForInputCharacter(NSString *text) {
  if (text.length != 1) return UINT16_MAX;
  switch ([text.lowercaseString characterAtIndex:0]) {
    case 'a': return kVK_ANSI_A; case 'b': return kVK_ANSI_B;
    case 'c': return kVK_ANSI_C; case 'd': return kVK_ANSI_D;
    case 'e': return kVK_ANSI_E; case 'f': return kVK_ANSI_F;
    case 'g': return kVK_ANSI_G; case 'h': return kVK_ANSI_H;
    case 'i': return kVK_ANSI_I; case 'j': return kVK_ANSI_J;
    case 'k': return kVK_ANSI_K; case 'l': return kVK_ANSI_L;
    case 'm': return kVK_ANSI_M; case 'n': return kVK_ANSI_N;
    case 'o': return kVK_ANSI_O; case 'p': return kVK_ANSI_P;
    case 'q': return kVK_ANSI_Q; case 'r': return kVK_ANSI_R;
    case 's': return kVK_ANSI_S; case 't': return kVK_ANSI_T;
    case 'u': return kVK_ANSI_U; case 'v': return kVK_ANSI_V;
    case 'w': return kVK_ANSI_W; case 'x': return kVK_ANSI_X;
    case 'y': return kVK_ANSI_Y; case 'z': return kVK_ANSI_Z;
    case '0': return kVK_ANSI_0; case '1': return kVK_ANSI_1;
    case '2': return kVK_ANSI_2; case '3': return kVK_ANSI_3;
    case '4': return kVK_ANSI_4; case '5': return kVK_ANSI_5;
    case '6': return kVK_ANSI_6; case '7': return kVK_ANSI_7;
    case '8': return kVK_ANSI_8; case '9': return kVK_ANSI_9;
    case ' ': return kVK_Space; case ',': return kVK_ANSI_Comma;
    case '.': return kVK_ANSI_Period; case ';': return kVK_ANSI_Semicolon;
    case '/': return kVK_ANSI_Slash; case '[': return kVK_ANSI_LeftBracket;
    case ']': return kVK_ANSI_RightBracket; case '\'': return kVK_ANSI_Quote;
    // TextKit and Electron may send arrows through inputText:client: as
    // AppKit function characters instead of forwarding an NSEvent.
    case NSUpArrowFunctionKey: return kVK_UpArrow;
    case NSDownArrowFunctionKey: return kVK_DownArrow;
    case NSLeftArrowFunctionKey: return kVK_LeftArrow;
    case NSRightArrowFunctionKey: return kVK_RightArrow;
    case NSPageUpFunctionKey: return kVK_PageUp;
    case NSPageDownFunctionKey: return kVK_PageDown;
    default: return UINT16_MAX;
  }
}

static NSString *GYChinesePunctuationForEvent(NSEvent *event, BOOL *openingSingleQuote, BOOL *openingDoubleQuote) {
  const BOOL shifted = (event.modifierFlags & NSEventModifierFlagShift) != 0;
  switch (event.keyCode) {
    case kVK_ANSI_Comma: return shifted ? @"《" : @"，";
    case kVK_ANSI_Period: return shifted ? @"》" : @"。";
    case kVK_ANSI_Semicolon: return shifted ? @"：" : @"；";
    case kVK_ANSI_Slash: return shifted ? @"？" : @"、";
    case kVK_ANSI_LeftBracket: return shifted ? @"｛" : @"【";
    case kVK_ANSI_RightBracket: return shifted ? @"｝" : @"】";
    case kVK_ANSI_1: return shifted ? @"！" : nil;
    case kVK_ANSI_Quote: {
      BOOL *opening = shifted ? openingDoubleQuote : openingSingleQuote;
      NSString *punctuation = shifted ? (*opening ? @"“" : @"”") : (*opening ? @"‘" : @"’");
      *opening = !*opening;
      return punctuation;
    }
    default: return nil;
  }
}

@implementation GYInputController {
  GYRimeBridge *_engine;
  GYCandidatePanel *_candidatePanel;
  NSArray<NSString *> *_candidates;
  NSString *_composition;
  NSUInteger _candidateOffset;
  NSUInteger _selectedCandidateIndex;
  BOOL _expandedCandidates;
  GYInputMode _mode;
  BOOL _shiftPending;
  BOOL _shiftUsed;
  BOOL _openingSingleQuote;
  BOOL _openingDoubleQuote;
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
  _candidatePanel = [[GYCandidatePanel alloc]
      initWithSelectionHandler:^(NSUInteger index) { [weakSelf selectDisplayedCandidateAtIndex:index]; }
      previousPageHandler:^{ [weakSelf moveUpCandidateView]; }
      nextPageHandler:^{ [weakSelf moveDownCandidateView]; }
      toggleExpandedHandler:^{ [weakSelf toggleCandidateExpansion]; }
      openSettingsHandler:^{ [weakSelf showPreferences:nil]; }];
  _composition = @"";
  _candidates = @[];
  _candidateOffset = 0;
  _selectedCandidateIndex = 0;
  _expandedCandidates = NO;
  _mode = GYSettingsStore.sharedStore.inputMode;
  [_engine setInputMode:_mode];
  _shiftPending = NO;
  _shiftUsed = NO;
  _openingSingleQuote = YES;
  _openingDoubleQuote = YES;
  [GYUpdateService.sharedService checkForUpdatesIfNeeded];
  return self;
}

- (void)applyInputMode:(GYInputMode)mode {
  if (_mode == mode) return;
  [self cancelComposition];
  _mode = mode;
  GYSettingsStore.sharedStore.inputMode = mode;
  [_engine setInputMode:mode];
  // A bare Shift must visibly confirm exactly which of the shared GY modes is
  // active.  EN has no candidate strip of its own, so without this badge the
  // Mac build changed modes silently while Windows announced it.
  [_candidatePanel showModeTitle:GYCompactModeTitle(mode) forClient:self.client];
}

- (void)toggleDirectInput {
  if (_mode == GYInputModeEnglish) {
    [self applyInputMode:GYSettingsStore.sharedStore.lastChineseMode];
  } else {
    [self applyInputMode:GYInputModeEnglish];
  }
}

// InputMethodKit creates an input controller per text client.  Settings are
// shared, so a mode change made in one application's menu or Settings window
// can otherwise leave another idle controller with an old in-memory mode.
// Synchronize before interpreting a bare Shift; never interrupt an active
// composition merely because another client changed the saved preference.
- (void)synchronizeIdleModeFromSettings {
  if (_composition.length != 0) return;
  GYInputMode storedMode = GYSettingsStore.sharedStore.inputMode;
  if (_mode == storedMode) return;
  _mode = storedMode;
  [_engine setInputMode:storedMode];
}

- (void)selectMode:(NSMenuItem *)sender {
  [self applyInputMode:(GYInputMode)sender.tag];
}
- (void)showPreferences:(id)sender {
  (void)sender;
  [GYPreferencesController.sharedController show];
}

- (NSUInteger)displayedCandidatePageSize {
  return _expandedCandidates ? GYExpandedCandidatePageSize : GYCollapsedCandidatePageSize;
}

- (NSArray<NSString *> *)displayedCandidates {
  if (_candidateOffset >= _candidates.count) return @[];
  NSUInteger length = MIN([self displayedCandidatePageSize], _candidates.count - _candidateOffset);
  return [_candidates subarrayWithRange:NSMakeRange(_candidateOffset, length)];
}

- (NSUInteger)selectedIndexInDisplayedCandidates {
  NSArray<NSString *> *displayed = [self displayedCandidates];
  if (displayed.count == 0 || _selectedCandidateIndex < _candidateOffset) return 0;
  return MIN(_selectedCandidateIndex - _candidateOffset, displayed.count - 1);
}

- (BOOL)canShowPreviousCandidatePage {
  // In the expanded grid, ↑ is always a meaningful inverse action: it moves
  // one row up, crosses to the prior Rime page, or folds the first row back
  // into the compact strip.  This keeps the on-screen arrow honest.
  return _expandedCandidates;
}

- (BOOL)canShowNextCandidatePage {
  if (!_expandedCandidates) return _candidates.count > GYCollapsedCandidatePageSize;
  NSUInteger visibleCount = MIN(_candidates.count, GYExpandedCandidatePageSize);
  return _selectedCandidateIndex + GYCandidateRowSize < visibleCount || _engine.canPageDown;
}

- (NSArray<NSString *> *)candidatesForCurrentCodeFromRime:(NSArray<NSString *> *)rimeCandidates {
  // Local phrases belong at the start of the first Rime page only. Repeating
  // them after every PageDown would make the 5 × 5 browser appear to loop.
  if (_engine.currentPageNumber != 0) return rimeCandidates;
  NSMutableOrderedSet<NSString *> *result = [NSMutableOrderedSet orderedSet];
  for (NSString *phrase in [GYSettingsStore.sharedStore customPhrasesForCode:_composition]) {
    [result addObject:[_engine localCandidateForPhrase:phrase inputMode:_mode]];
  }
  [result addObjectsFromArray:rimeCandidates];
  return result.array;
}

- (void)refreshCandidatesFromCurrentRimePage {
  _candidates = [self candidatesForCurrentCodeFromRime:[_engine currentCandidates]];
}

- (void)resetCandidateViewport {
  _candidateOffset = 0;
  _selectedCandidateIndex = 0;
  _expandedCandidates = NO;
}


- (nullable NSString *)commitDisplayedCandidateAtIndex:(NSUInteger)index {
  NSUInteger candidateIndex = _candidateOffset + index;
  if (candidateIndex >= _candidates.count) return nil;
  NSString *candidate = _candidates[candidateIndex];
  NSArray<NSString *> *rimeCandidates = [_engine currentCandidates];
  // Local phrase lists can contain several entries for one code.  If a phrase
  // already exists in Rime, commit through Rime so it participates in local
  // learning; otherwise commit the purely local phrase directly.  Looking up
  // by displayed text also keeps the index correct after de-duplication.
  NSUInteger rimeIndex = [rimeCandidates indexOfObject:candidate];
  if (rimeIndex != NSNotFound) return [_engine commitCandidateAtIndex:rimeIndex];
  return candidate;
}

- (void)selectDisplayedCandidateAtIndex:(NSUInteger)index {
  NSArray<NSString *> *displayed = [self displayedCandidates];
  if (index >= displayed.count) return;
  NSString *commit = [self commitDisplayedCandidateAtIndex:index];
  [self commitText:commit ?: displayed[index]];
}

- (void)showPreviousCandidatePage {
  if (_composition.length == 0) return;
  NSUInteger pageSize = [self displayedCandidatePageSize];
  if (_candidateOffset >= pageSize) {
    _candidateOffset -= pageSize;
  } else if ([_engine pageUp]) {
    [self refreshCandidatesFromCurrentRimePage];
    if (!_expandedCandidates && _candidates.count > pageSize) {
      _candidateOffset = ((_candidates.count - 1) / pageSize) * pageSize;
    }
  } else {
    return;
  }
  _selectedCandidateIndex = _candidateOffset;
  [self updateMarkedTextForClient:self.client];
}

- (void)showNextCandidatePage {
  if (_composition.length == 0) return;
  NSUInteger pageSize = [self displayedCandidatePageSize];
  if (_candidateOffset + pageSize < _candidates.count) {
    _candidateOffset += pageSize;
  } else if ([_engine pageDown]) {
    [self refreshCandidatesFromCurrentRimePage];
    _candidateOffset = 0;
  } else {
    return;
  }
  _selectedCandidateIndex = _candidateOffset;
  [self updateMarkedTextForClient:self.client];
}

- (void)toggleCandidateExpansion {
  if (_candidates.count <= GYCollapsedCandidatePageSize) return;
  _expandedCandidates = !_expandedCandidates;
  NSUInteger pageSize = [self displayedCandidatePageSize];
  _candidateOffset = (_selectedCandidateIndex / pageSize) * pageSize;
  [self updateMarkedTextForClient:self.client];
}

- (void)moveCandidateSelectionBy:(NSInteger)delta {
  if (_candidates.count == 0) return;
  NSInteger count = (NSInteger)_candidates.count;
  NSInteger next = ((NSInteger)_selectedCandidateIndex + delta) % count;
  if (next < 0) next += count;
  _selectedCandidateIndex = (NSUInteger)next;
  NSUInteger pageSize = [self displayedCandidatePageSize];
  _candidateOffset = (_selectedCandidateIndex / pageSize) * pageSize;
  [self updateMarkedTextForClient:self.client];
}

- (void)moveDownCandidateView {
  // Internal beta telemetry: intentionally records only state counts, never
  // pinyin or candidate text. It distinguishes a missed key from a panel
  // presentation issue in the field.
  os_log_info(GYInputEventLog(), "down action compositionLength=%{public}lu candidateCount=%{public}lu expanded=%{public}d",
      (unsigned long)_composition.length, (unsigned long)_candidates.count, _expandedCandidates);
  if (_composition.length == 0) return;
  if (!_expandedCandidates) {
    // ↓ opens the 5 × 5 grid.  Once it is open, ↓ moves the selected chip one
    // *row* (five candidates), rather than jumping a whole 25-candidate grid.
    // This is the same continuous-browse contract as the Windows build.
    _expandedCandidates = YES;
    _candidateOffset = 0;
    [self updateMarkedTextForClient:self.client];
    return;
  }

  NSUInteger visibleCount = MIN(_candidates.count, GYExpandedCandidatePageSize);
  if (_selectedCandidateIndex + GYCandidateRowSize < visibleCount) {
    _selectedCandidateIndex += GYCandidateRowSize;
    _candidateOffset = 0;
    [self updateMarkedTextForClient:self.client];
  } else if ([_engine pageDown]) {
    // Preserve the visual column when crossing from the fifth row to the next
    // Rime page, then continue the same one-row movement on that page.
    NSUInteger column = _selectedCandidateIndex % GYCandidateRowSize;
    [self refreshCandidatesFromCurrentRimePage];
    _candidateOffset = 0;
    _selectedCandidateIndex = MIN(column, _candidates.count == 0 ? 0 : _candidates.count - 1);
    [self updateMarkedTextForClient:self.client];
  }
}

// ↑ is the exact inverse of ↓: move one candidate row toward the beginning.
// At the beginning of the first Rime page, one extra ↑ folds the grid back to
// the compact one-row strip.  Keep this in a concrete action as well as the
// IMK selector route because TextKit clients do not all use the same callback.
- (void)moveUpCandidateView {
  if (_composition.length == 0) return;
  if (!_expandedCandidates) return;

  if (_selectedCandidateIndex >= GYCandidateRowSize) {
    _selectedCandidateIndex -= GYCandidateRowSize;
    _candidateOffset = 0;
    [self updateMarkedTextForClient:self.client];
    return;
  }

  if ([_engine pageUp]) {
    NSUInteger column = _selectedCandidateIndex % GYCandidateRowSize;
    [self refreshCandidatesFromCurrentRimePage];
    _candidateOffset = 0;
    NSUInteger visibleCount = MIN(_candidates.count, GYExpandedCandidatePageSize);
    NSUInteger lastRowStart = visibleCount == 0 ? 0 : ((visibleCount - 1) / GYCandidateRowSize) * GYCandidateRowSize;
    _selectedCandidateIndex = MIN(lastRowStart + column, visibleCount == 0 ? 0 : visibleCount - 1);
    [self updateMarkedTextForClient:self.client];
    return;
  }

  // There is no earlier candidate row.  This final ↑ intentionally returns
  // from the 5 × 5 browser to the normal one-line candidate strip.
  _expandedCandidates = NO;
  _candidateOffset = 0;
  [self updateMarkedTextForClient:self.client];
}

// Some TextKit clients resolve the standard selector themselves instead of
// calling didCommandBySelector:client:.  Keep a concrete action as a final
// InputMethodKit-compatible route for an unmodified ↓ key.
- (void)moveDown:(id)sender {
  (void)sender;
  os_log_info(GYInputEventLog(), "down route=direct-action");
  [self moveDownCandidateView];
}

- (void)moveUp:(id)sender {
  (void)sender;
  [self moveUpCandidateView];
}

- (void)commitDefaultCandidateOrRawComposition {
  if (_composition.length == 0) return;
  NSArray<NSString *> *displayed = [self displayedCandidates];
  NSUInteger selected = [self selectedIndexInDisplayedCandidates];
  NSString *commit = displayed.count == 0 ? _composition : [self commitDisplayedCandidateAtIndex:selected];
  [self commitText:commit ?: _composition];
}

- (NSMenu *)menu {
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"GY 输入法"];
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
  [menu addItem:preferences];
  NSMenuItem *about = [[NSMenuItem alloc] initWithTitle:@"关于 GY 输入法" action:@selector(showAbout:) keyEquivalent:@""];
  about.target = self;
  [menu addItem:about];
  NSMenuItem *status = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"GY Input · %@", GYInputModeTitle(_mode)] action:nil keyEquivalent:@""];
  status.enabled = NO;
  [menu addItem:status];
  return menu;
}

- (void)showAbout:(id)sender {
  (void)sender;
  [GYPreferencesController.sharedController showAbout];
}

- (NSArray *)candidates:(id)sender { return _candidates; }

- (id)composedString:(id)sender {
  (void)sender;
  return _composition;
}

- (NSAttributedString *)originalString:(id)sender {
  (void)sender;
  return [[NSAttributedString alloc] initWithString:_composition];
}

- (void)commitComposition:(id)sender {
  (void)sender;
  [self commitDefaultCandidateOrRawComposition];
}

- (void)candidateSelected:(NSAttributedString *)candidateString {
  NSString *text = candidateString.string;
  if (text.length == 0) return;
  NSUInteger index = [_candidates indexOfObject:text];
  if (index == NSNotFound) {
    [self commitText:text];
    return;
  }
  _selectedCandidateIndex = index;
  _candidateOffset = (index / [self displayedCandidatePageSize]) * [self displayedCandidatePageSize];
  [self commitDefaultCandidateOrRawComposition];
}

- (BOOL)inputText:(NSString *)text key:(NSInteger)keyCode modifiers:(NSUInteger)flags client:(id)client {
  // InputMethodKit's unpacked-key route sends non-text keys (including ↓) as
  // an empty string plus their physical virtual-key code.  Rejecting empty
  // text here made the key fall through to the host application before the
  // candidate state machine could expand its 5 × 5 view.
  if (keyCode < 0 || keyCode > UINT16_MAX) return NO;
  if ((unsigned short)keyCode == kVK_DownArrow) {
    os_log_info(GYInputEventLog(), "down route=unpacked textLength=%{public}lu flags=%{public}lu",
        (unsigned long)text.length, (unsigned long)flags);
  }
  NSString *characters = text ?: @"";
  NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                    location:NSZeroPoint
                               modifierFlags:flags
                                   timestamp:0
                                windowNumber:0
                                     context:nil
                                  characters:characters
                 charactersIgnoringModifiers:characters
                                   isARepeat:NO
                                     keyCode:(unsigned short)keyCode];
  return [self handleEvent:event client:client];
}

- (BOOL)inputText:(NSString *)text client:(id)client {
  unsigned short keyCode = GYKeyCodeForInputCharacter(text);
  if (keyCode == UINT16_MAX) return NO;
  if (keyCode == kVK_DownArrow) {
    os_log_info(GYInputEventLog(), "down route=text-function-character");
  }
  return [self inputText:text key:keyCode modifiers:0 client:client];
}

- (NSUInteger)recognizedEvents:(id)sender {
  (void)sender;
  // Claim both channels used by the composition state machine. Explicitly
  // including flags-changed also makes standalone Shift deterministic.
  return NSEventMaskKeyDown | NSEventMaskFlagsChanged;
}

// WebKit commonly sends non-text keys (space, escape, delete and paging) as
// commands rather than NSEvents.  Keep them on the same conversion path as
// AppKit so a visible candidate can always be accepted or dismissed.
- (BOOL)didCommandBySelector:(SEL)selector client:(id)client {
  NSString *command = NSStringFromSelector(selector);
  if ([command containsString:@"Down"]) {
    os_log_info(GYInputEventLog(), "down route=selector selector=%{public}@", command);
  }
  if ([command isEqualToString:@"insertSpace:"] && _composition.length != 0) {
    [self commitDefaultCandidateOrRawComposition];
    return YES;
  }
  if ([command isEqualToString:@"cancelOperation:"] && _composition.length != 0) {
    [self cancelComposition];
    return YES;
  }
  if ([command isEqualToString:@"deleteBackward:"] && _composition.length != 0) {
    _composition = [_composition substringToIndex:_composition.length - 1];
    _candidates = [self candidatesForCurrentCodeFromRime:[_engine candidatesForCode:_composition]];
    [self resetCandidateViewport];
    if (_composition.length == 0) [self cancelComposition];
    else [self updateMarkedTextForClient:client];
    return YES;
  }
  // NSTextView/WebKit often translates arrows to selectors instead of
  // forwarding NSEvents. Treat this path exactly like the Windows TSF key
  // state machine: ↓ expands first, then moves expanded pages; arrows never
  // require clicking the disclosure control.
  if (([command isEqualToString:@"pageUp:"] || [command isEqualToString:@"scrollPageUp:"]) && _composition.length != 0) {
    [self showPreviousCandidatePage];
    return YES;
  }
  if ([command isEqualToString:@"moveUp:"] && _composition.length != 0) {
    [self moveUpCandidateView];
    return YES;
  }
  if (([command isEqualToString:@"pageDown:"] || [command isEqualToString:@"scrollPageDown:"]) && _composition.length != 0) {
    if ([self canShowNextCandidatePage]) [self showNextCandidatePage];
    return YES;
  }
  if ([command isEqualToString:@"moveDown:"] && _composition.length != 0) {
    [self moveDownCandidateView];
    return YES;
  }
  if ([command isEqualToString:@"moveLeft:"] && _composition.length != 0) { [self moveCandidateSelectionBy:-1]; return YES; }
  if ([command isEqualToString:@"moveRight:"] && _composition.length != 0) { [self moveCandidateSelectionBy:1]; return YES; }
  return NO;
}

// The direct event path avoids binding normal application shortcuts to the
// IME. Command/Control/Option/Fn always return NO to the focused application.
- (BOOL)handleEvent:(NSEvent *)event client:(id)client {
  const NSEventModifierFlags blockingModifiers = NSEventModifierFlagCommand |
      NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagFunction;
  if (event.type == NSEventTypeFlagsChanged &&
      (event.keyCode == kVK_Shift || event.keyCode == kVK_RightShift)) {
    [self synchronizeIdleModeFromSettings];
    if ((event.modifierFlags & NSEventModifierFlagShift) != 0) {
      _shiftPending = YES;
      _shiftUsed = NO;
    } else if (_shiftPending) {
      if (!_shiftUsed) [self toggleDirectInput];
      _shiftPending = NO;
      _shiftUsed = NO;
    }
    return YES;
  }
  if (event.type != NSEventTypeKeyDown) return NO;
  [self synchronizeIdleModeFromSettings];
  // A missing/corrupt Rime workspace must never turn the selected input source
  // into a keyboard black hole. Clear any stale marked text and let the client
  // receive the key unchanged until the engine is healthy again.
  if (![_engine isReady]) {
    if (_composition.length != 0) [self cancelComposition];
    return NO;
  }

  // Laptop and remote keyboards can include the Fn bit with an arrow key.
  // Fn is not an application shortcut, so handle plain ↑/↓ before the
  // generic shortcut gate. Command/Control/Option/Shift remain available to
  // the focused app for its normal navigation and selection shortcuts.
  const NSEventModifierFlags candidateNavigationModifiers = NSEventModifierFlagCommand |
      NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift;
  if (event.keyCode == kVK_DownArrow && _composition.length != 0 &&
      (event.modifierFlags & candidateNavigationModifiers) == 0) {
    os_log_info(GYInputEventLog(), "down route=event flags=%{public}lu", (unsigned long)event.modifierFlags);
    [self moveDownCandidateView];
    return YES;
  }
  if (event.keyCode == kVK_UpArrow && _composition.length != 0 &&
      (event.modifierFlags & candidateNavigationModifiers) == 0) {
    os_log_info(GYInputEventLog(), "up route=event flags=%{public}lu", (unsigned long)event.modifierFlags);
    [self moveUpCandidateView];
    return YES;
  }

  if ((event.modifierFlags & blockingModifiers) != 0) {
    _shiftUsed = _shiftPending;
    return NO;
  }
  if (_shiftPending) _shiftUsed = YES;

  if (event.keyCode == kVK_Escape && _composition.length != 0) {
    [self cancelComposition];
    return YES;
  }
  if (event.keyCode == kVK_Return && _composition.length != 0) {
    // Return explicitly keeps pinyin as ASCII. It must never toggle EN mode.
    [self commitText:_composition];
    return YES;
  }

  if (event.keyCode == kVK_Delete && _composition.length != 0) {
    _composition = [_composition substringToIndex:_composition.length - 1];
    _candidates = [self candidatesForCurrentCodeFromRime:[_engine candidatesForCode:_composition]];
    [self resetCandidateViewport];
    if (_composition.length == 0) [self cancelComposition];
    else [self updateMarkedTextForClient:client];
    return YES;
  }

  if (GYInputModeIsChinese(_mode)) {
    NSString *punctuation = GYChinesePunctuationForEvent(event, &_openingSingleQuote, &_openingDoubleQuote);
    if (punctuation != nil) {
      [self commitDefaultCandidateOrRawComposition];
      [self commitText:punctuation];
      return YES;
    }
    // Shift+letter and Shift+number are normal application input. Only a lone
    // Shift toggles modes; shifted punctuation was handled above.
    if ((event.modifierFlags & NSEventModifierFlagShift) != 0) return NO;
  }

  if (event.keyCode == kVK_Space && _composition.length != 0) {
    [self commitDefaultCandidateOrRawComposition];
    return YES;
  }
  if (event.keyCode == kVK_PageUp && _composition.length != 0) {
    [self showPreviousCandidatePage];
    return YES;
  }
  if (event.keyCode == kVK_UpArrow && _composition.length != 0) {
    [self moveUpCandidateView];
    return YES;
  }
  if (event.keyCode == kVK_PageDown && _composition.length != 0) {
    if ([self canShowNextCandidatePage]) [self showNextCandidatePage];
    return YES;
  }
  if (event.keyCode == kVK_LeftArrow && _composition.length != 0) { [self moveCandidateSelectionBy:-1]; return YES; }
  if (event.keyCode == kVK_RightArrow && _composition.length != 0) { [self moveCandidateSelectionBy:1]; return YES; }

  NSInteger selectionIndex = GYCandidateIndexForKeyCode(event.keyCode);
  if (selectionIndex != NSNotFound && [self displayedCandidates].count != 0) {
    NSUInteger index = (NSUInteger)selectionIndex;
    if (index < [self displayedCandidates].count) { [self selectDisplayedCandidateAtIndex:index]; return YES; }
  }
  // Windows reserves 1–5 for the visible row and consumes the other digit
  // keys while a composition is active.  Letting 6–9 fall through would both
  // imply nonexistent shortcuts and leak raw digits into the target app.
  if (_composition.length != 0 &&
      [event.charactersIgnoringModifiers rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet].location != NSNotFound) {
    return YES;
  }

  NSString *text = event.charactersIgnoringModifiers.lowercaseString;
  if (!GYInputModeIsChinese(_mode) || text.length != 1 || [text rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location == NSNotFound) {
    return NO;
  }
  _composition = [_composition stringByAppendingString:text];
  _candidates = [self candidatesForCurrentCodeFromRime:[_engine candidatesForCode:_composition]];
  [self resetCandidateViewport];
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
  [self resetCandidateViewport];
  [_candidatePanel hide];
}

- (void)updateMarkedTextForClient:(id)client {
  if (_composition.length == 0) return;
  NSAttributedString *marked = [[NSAttributedString alloc] initWithString:_composition];
  [client setMarkedText:marked
          selectionRange:NSMakeRange(_composition.length, 0)
        replacementRange:NSMakeRange(NSNotFound, 0)];
  NSArray<NSString *> *displayed = [self displayedCandidates];
  [_candidatePanel showWithCandidates:displayed
                         selectedIndex:[self selectedIndexInDisplayedCandidates]
                           pageNumber:_engine.currentPageNumber * 5 + _candidateOffset / [self displayedCandidatePageSize]
                      canGoPreviousPage:[self canShowPreviousCandidatePage]
                          canGoNextPage:[self canShowNextCandidatePage]
                              expanded:_expandedCandidates
                   canExpandCandidates:_candidates.count > GYCollapsedCandidatePageSize
                         inputModeTitle:GYCompactModeTitle(_mode)
                             forClient:client];
}

- (void)cancelComposition {
  [_engine clearComposition];
  _composition = @"";
  _candidates = @[];
  [self resetCandidateViewport];
  [_candidatePanel hide];
  id client = self.client;
  if ([client respondsToSelector:@selector(unmarkText)]) {
    [client unmarkText];
  } else if (client != nil) {
    [client setMarkedText:@"" selectionRange:NSMakeRange(0, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
  }
}

- (void)inputControllerWillClose {
  [self cancelComposition];
  [super inputControllerWillClose];
}

@end
