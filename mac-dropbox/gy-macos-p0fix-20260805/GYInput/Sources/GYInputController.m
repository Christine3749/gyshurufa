#import "GYInputController.h"
#import "GYRimeBridge.h"
#import "GYInputMode.h"
#import "GYSettingsStore.h"
#import "GYPreferencesController.h"
#import <Carbon/HIToolbox/Events.h>

@implementation GYInputController {
  GYRimeBridge *_engine;
  IMKCandidates *_candidatePanel;
  NSArray<NSString *> *_candidates;
  NSString *_composition;
  GYInputMode _mode;
  BOOL _shiftPending;
  BOOL _shiftUsed;
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
  _candidatePanel = [[IMKCandidates alloc] initWithServer:server panelType:kIMKSingleColumnScrollingCandidatePanel];
  [_candidatePanel setDismissesAutomatically:YES];
  _composition = @"";
  _candidates = @[];
  _mode = GYSettingsStore.sharedStore.inputMode;
  [_engine setInputMode:_mode];
  _shiftPending = NO;
  _shiftUsed = NO;
  return self;
}

- (void)applyInputMode:(GYInputMode)mode {
  if (_mode == mode) return;
  [self cancelComposition];
  _mode = mode;
  GYSettingsStore.sharedStore.inputMode = mode;
  [_engine setInputMode:mode];
}

- (void)toggleDirectInput {
  if (_mode == GYInputModeEnglish) {
    [self applyInputMode:GYSettingsStore.sharedStore.lastChineseMode];
  } else {
    [self applyInputMode:GYInputModeEnglish];
  }
}

- (void)selectMode:(NSMenuItem *)sender {
  [self applyInputMode:(GYInputMode)sender.tag];
}
- (void)showPreferences:(id)sender {
  (void)sender;
  [GYPreferencesController.sharedController show];
}


// Commits the displayed candidate at index, then refreshes any composition
// remainder Rime kept (sentence-style partial commits). A custom phrase at
// index 0 bypasses Rime, so the engine composition is cleared instead.
- (void)commitCandidateSelectionAtIndex:(NSUInteger)index
                                 suffix:(nullable NSString *)suffix
                                 client:(id)client {
  if (index >= _candidates.count || client == nil) return;
  NSString *phrase = GYSettingsStore.sharedStore.customPhrases[_composition.lowercaseString];
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
  NSString *commit = [_engine commitCandidateAtIndex:rimeIndex];
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
    [_candidatePanel hide];
    return;
  }
  _composition = rest;
  _candidates = [GYSettingsStore.sharedStore candidatesByAddingCustomPhrases:[_engine currentCandidates]
                                                                     forCode:_composition];
  [self updateMarkedTextForClient:client];
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
  NSMenuItem *status = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"GY Input · %@", GYInputModeTitle(_mode)] action:nil keyEquivalent:@""];
  status.enabled = NO;
  [menu addItem:status];
  return menu;
}

- (NSArray *)candidates:(id)sender { return _candidates; }

- (void)candidateSelected:(NSAttributedString *)candidateString {
  NSString *text = candidateString.string;
  if (text.length == 0) return;
  NSUInteger index = [_candidates indexOfObject:text];
  if (index == NSNotFound) {
    [self commitText:text];
    return;
  }
  [self commitCandidateSelectionAtIndex:index suffix:nil client:self.client];
}

// The direct event path avoids binding normal application shortcuts to the
// IME. Command/Control/Option/Fn always return NO to the focused application.
- (BOOL)handleEvent:(NSEvent *)event client:(id)client {
  const NSEventModifierFlags blockingModifiers = NSEventModifierFlagCommand |
      NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagFunction;
  if (event.type == NSEventTypeFlagsChanged &&
      (event.keyCode == kVK_Shift || event.keyCode == kVK_RightShift)) {
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
  if (_composition.length == 0 && _mode != GYSettingsStore.sharedStore.inputMode) {
    _mode = GYSettingsStore.sharedStore.inputMode;
    [_engine setInputMode:_mode];
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
    _candidates = [GYSettingsStore.sharedStore candidatesByAddingCustomPhrases:[_engine candidatesForCode:_composition] forCode:_composition];
    if (_composition.length == 0) [self cancelComposition];
    else [self updateMarkedTextForClient:client];
    return YES;
  }
  if (event.keyCode == kVK_Space && _candidates.count != 0) {
    [self commitCandidateSelectionAtIndex:0 suffix:nil client:client];
    return YES;
  }
  if (event.keyCode == kVK_PageUp && _composition.length != 0 && [_engine pageUp]) {
    _candidates = [_engine currentCandidates];
    [self updateMarkedTextForClient:client];
    return YES;
  }
  if (event.keyCode == kVK_PageDown && _composition.length != 0 && [_engine pageDown]) {
    _candidates = [_engine currentCandidates];
    [self updateMarkedTextForClient:client];
    return YES;
  }

  if (event.keyCode >= kVK_ANSI_1 && event.keyCode <= kVK_ANSI_9 && _candidates.count != 0) {
    NSUInteger index = event.keyCode - kVK_ANSI_1;
    if (index < _candidates.count) {
      [self commitCandidateSelectionAtIndex:index suffix:nil client:client];
      return YES;
    }
  }

  if (GYInputModeIsChinese(_mode)) {
    NSDictionary<NSString *, NSString *> *punctuation = @{@",": @"，", @".": @"。", @"?": @"？", @"!": @"！", @";": @"；", @":": @"："};
    NSString *converted = punctuation[event.characters];
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

  NSString *text = event.charactersIgnoringModifiers.lowercaseString;
  if (!GYInputModeIsChinese(_mode) || text.length != 1 || [text rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location == NSNotFound) {
    return NO;
  }
  _composition = [_composition stringByAppendingString:text];
  _candidates = [GYSettingsStore.sharedStore candidatesByAddingCustomPhrases:[_engine candidatesForCode:_composition] forCode:_composition];
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
  [_candidatePanel hide];
}

- (void)updateMarkedTextForClient:(id)client {
  if (_composition.length == 0) return;
  NSAttributedString *marked = [[NSAttributedString alloc] initWithString:_composition];
  [client setMarkedText:marked
          selectionRange:NSMakeRange(_composition.length, 0)
        replacementRange:NSMakeRange(NSNotFound, 0)];
  [_candidatePanel updateCandidates];
  [_candidatePanel show:kIMKLocateCandidatesBelowHint];
}

- (void)cancelComposition {
  [_engine clearComposition];
  _composition = @"";
  _candidates = @[];
  [_candidatePanel hide];
  [super cancelComposition];
}

- (void)inputControllerWillClose {
  [self cancelComposition];
  [super inputControllerWillClose];
}

@end