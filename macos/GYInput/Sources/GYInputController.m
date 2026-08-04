#import <Carbon/Carbon.h>
#import <InputMethodKit/InputMethodKit.h>
#import "GYComposition.h"
#import "GYDiagnostics.h"
#import "GYInputMode.h"
#import "GYLexicon.h"

@interface GYInputController : IMKInputController
@end

@implementation GYInputController {
  __weak id _activeClient;
  GYComposition *_composition;
  IMKCandidates *_candidatePanel;
  NSInteger _selection;
  BOOL _hasMarkedText;
}

- (instancetype)initWithServer:(IMKServer *)server delegate:(id)delegate client:(id)client {
  self = [super initWithServer:server delegate:delegate client:client];
  if (self) {
    _activeClient = client;
    _composition = [GYComposition new];
    _candidatePanel = [[IMKCandidates alloc] initWithServer:server panelType:kIMKScrollingGridCandidatePanel];
    [_candidatePanel setDismissesAutomatically:NO];
    [_candidatePanel setAttributes:@{
      NSFontAttributeName: [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold],
      NSForegroundColorAttributeName: [NSColor colorWithWhite:0.965 alpha:1],
      NSBackgroundColorDocumentAttribute: [NSColor colorWithRed:0.067 green:0.075 blue:0.094 alpha:1],
      IMKCandidatesSendServerKeyEventFirst: @YES,
    }];
    GYTrace(@"controller-init");
  }
  return self;
}

- (void)activateServer:(id)sender { _activeClient = sender; GYTrace(@"controller-activate"); }

- (void)deactivateServer:(id)sender {
  (void)sender;
  [self clearComposition];
  _activeClient = nil;
  GYTrace(@"controller-deactivate");
}

- (id)currentClient { return _activeClient ?: self.client; }

- (void)showComposition {
  id client = self.currentClient;
  if (client && _composition.code.length) {
    [client setMarkedText:[[NSAttributedString alloc] initWithString:_composition.code]
            selectionRange:NSMakeRange(_composition.code.length, 0)
          replacementRange:NSMakeRange(NSNotFound, 0)];
    _hasMarkedText = YES;
  }
}

- (void)refreshCandidates {
  NSArray *visible = _composition.visibleCandidates;
  if (visible.count == 0) { [_candidatePanel hide]; return; }
  _selection = MIN(_selection, (NSInteger)visible.count - 1);
  [_candidatePanel updateCandidates];
  [_candidatePanel show:kIMKLocateCandidatesBelowHint];
  NSInteger identifier = [_candidatePanel candidateStringIdentifier:visible[(NSUInteger)_selection]];
  if (identifier != NSNotFound) [_candidatePanel selectCandidateWithIdentifier:identifier];
}

- (void)clearComposition {
  [_candidatePanel hide];
  [_composition clear];
  _selection = 0;
  id client = self.currentClient;
  if (_hasMarkedText && [client respondsToSelector:@selector(unmarkText)]) [client unmarkText];
  _hasMarkedText = NO;
}

- (void)commitText:(NSString *)text {
  if (text.length) [self.currentClient insertText:text replacementRange:NSMakeRange(NSNotFound, 0)];
  [self clearComposition];
}

- (void)commitSelectedCandidate {
  NSString *candidate = [_composition candidateAtVisibleIndex:_selection];
  if (candidate) [_composition learnCandidate:candidate];
  [self commitText:candidate ?: _composition.code];
}

- (NSArray *)candidates:(id)sender { (void)sender; return _composition.visibleCandidates; }
- (id)composedString:(id)sender { (void)sender; return _composition.code; }
- (NSAttributedString *)originalString:(id)sender { (void)sender; return [[NSAttributedString alloc] initWithString:_composition.code]; }
- (void)commitComposition:(id)sender { (void)sender; [self commitSelectedCandidate]; }

- (void)candidateSelected:(NSAttributedString *)candidateString {
  [_composition learnCandidate:candidateString.string];
  [self commitText:candidateString.string];
}

- (void)candidateSelectionChanged:(NSAttributedString *)candidateString {
  NSUInteger index = [_composition.visibleCandidates indexOfObject:candidateString.string];
  if (index != NSNotFound) _selection = (NSInteger)index;
}

- (void)setSelection:(NSInteger)selection {
  _selection = MAX(0, selection);
  [self refreshCandidates];
}

- (BOOL)moveSelectionForKey:(NSInteger)keyCode {
  NSArray *visible = _composition.visibleCandidates;
  if (visible.count == 0) return NO;
  if (keyCode == kVK_DownArrow && !_composition.expanded) { [_composition expand]; _selection = 0; [self refreshCandidates]; return YES; }
  if (keyCode == kVK_PageDown && [_composition nextPage]) { _selection = 0; [self refreshCandidates]; return YES; }
  if (keyCode == kVK_PageUp && [_composition previousPage]) { _selection = 0; [self refreshCandidates]; return YES; }
  if (keyCode == kVK_UpArrow && _selection < 5 && _composition.expanded && ![_composition previousPage]) {
    [_composition collapse]; _selection = 0; [self refreshCandidates]; return YES;
  }
  NSInteger delta = keyCode == kVK_LeftArrow ? -1 : keyCode == kVK_RightArrow ? 1 : keyCode == kVK_UpArrow ? -5 : keyCode == kVK_DownArrow ? 5 : 0;
  if (delta == 0) return NO;
  NSInteger target = _selection + delta;
  if (target < 0 || target >= (NSInteger)visible.count) return YES;
  [self setSelection:target];
  return YES;
}

- (BOOL)selectNumberForKey:(NSInteger)keyCode {
  NSArray<NSNumber *> *keys = @[@(kVK_ANSI_1), @(kVK_ANSI_2), @(kVK_ANSI_3), @(kVK_ANSI_4), @(kVK_ANSI_5)];
  NSUInteger index = [keys indexOfObject:@(keyCode)];
  if (index == NSNotFound || index >= _composition.visibleCandidates.count) return NO;
  _selection = (NSInteger)index;
  [self commitSelectedCandidate];
  return YES;
}

- (BOOL)inputText:(NSString *)string key:(NSInteger)keyCode modifiers:(NSUInteger)modifiers client:(id)client {
  _activeClient = client;
  GYTrace(@"text-event");
  NSEventModifierFlags blocked = NSEventModifierFlagCommand | NSEventModifierFlagControl |
      NSEventModifierFlagOption | NSEventModifierFlagFunction;
  if ((modifiers & blocked) != 0) return NO;
  if ((keyCode == kVK_Shift || keyCode == kVK_RightShift) && string.length == 0) {
    GYInputMode mode = [[GYInputModeStore sharedStore] cycleMode];
    [self clearComposition];
    GYTrace([NSString stringWithFormat:@"mode=%@", GYInputModeLabel(mode)]);
    return YES;
  }
  if (!GYInputModeUsesChinese(GYInputModeStore.sharedStore.mode)) {
    if (_composition.code.length) [self clearComposition];
    return NO;
  }
  if (keyCode == kVK_Escape && _composition.code.length) { [self clearComposition]; return YES; }
  if (keyCode == kVK_Delete) {
    if (![_composition deleteBackward]) return NO;
    _selection = 0;
    if (_composition.code.length) { [self showComposition]; [self refreshCandidates]; } else [self clearComposition];
    return YES;
  }
  if ([self moveSelectionForKey:keyCode]) return YES;
  if ([self selectNumberForKey:keyCode]) return YES;
  if ((keyCode == kVK_Space || keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter) && _composition.code.length) {
    [self commitSelectedCandidate];
    return YES;
  }
  NSString *code = [GYLexicon normalizedCode:string];
  if (code.length) {
    [_composition appendText:code mode:GYInputModeStore.sharedStore.mode];
    _selection = 0;
    [self showComposition];
    [self refreshCandidates];
    return YES;
  }
  if (_composition.code.length) [self commitSelectedCandidate];
  return NO;
}

- (NSMenu *)menu {
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"GY 输入法"];
  for (NSNumber *value in @[@(GYInputModeSimplified), @(GYInputModeTraditional), @(GYInputModeEnglish)]) {
    GYInputMode mode = value.integerValue;
    NSMenuItem *item = [menu addItemWithTitle:GYInputModeLabel(mode) action:@selector(selectMode:) keyEquivalent:@""];
    item.representedObject = value;
    item.state = GYInputModeStore.sharedStore.mode == mode ? NSControlStateValueOn : NSControlStateValueOff;
  }
  return menu;
}

- (void)selectMode:(NSMenuItem *)item {
  [[GYInputModeStore sharedStore] setMode:[(NSNumber *)item.representedObject integerValue]];
  [self clearComposition];
}

- (void)inputControllerWillClose { [self clearComposition]; [super inputControllerWillClose]; }

@end
