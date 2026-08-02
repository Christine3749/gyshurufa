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


- (nullable NSString *)commitDisplayedCandidateAtIndex:(NSUInteger)index {
  if (index >= _candidates.count) return nil;
  NSString *phrase = GYSettingsStore.sharedStore.customPhrases[_composition.lowercaseString];
  NSArray<NSString *> *rimeCandidates = [_engine currentCandidates];
  BOOL insertedCustomPhrase = phrase.length != 0 &&
      [_candidates.firstObject isEqualToString:phrase] &&
      ![rimeCandidates containsObject:phrase];
  if (insertedCustomPhrase && index == 0) return phrase;
  NSUInteger rimeIndex = insertedCustomPhrase ? index - 1 : index;
  return [_engine commitCandidateAtIndex:rimeIndex];
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
  NSString *commit = index == NSNotFound ? nil : [self commitDisplayedCandidateAtIndex:index];
  [self commitText:commit ?: text];
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
    NSString *commit = [self commitDisplayedCandidateAtIndex:0];
    [self commitText:commit ?: _candidates.firstObject];
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
      NSString *commit = [self commitDisplayedCandidateAtIndex:index];
      [self commitText:commit ?: _candidates[index]];
      return YES;
    }
  }

  if (GYInputModeIsChinese(_mode) && _composition.length == 0) {
    NSDictionary<NSString *, NSString *> *punctuation = @{@",": @"，", @".": @"。", @"?": @"？", @"!": @"！", @";": @"；", @":": @"："};
    NSString *converted = punctuation[event.characters];
    if (converted != nil) {
      [self commitText:converted];
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