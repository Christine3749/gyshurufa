#import <Carbon/Carbon.h>
#import <InputMethodKit/InputMethodKit.h>
#import "GYDiagnostics.h"
#import "GYInputMode.h"
#import "GYRimeSession.h"

@interface GYInputController : IMKInputController
@end

@implementation GYInputController {
  __weak id _activeClient;
  GYRimeSession *_rime;
  IMKCandidates *_candidatePanel;
  NSInteger _selection;
  BOOL _expanded;
  BOOL _hasMarkedText;
}

- (instancetype)initWithServer:(IMKServer *)server delegate:(id)delegate client:(id)client {
  self = [super initWithServer:server delegate:delegate client:client];
  if (self) {
    _activeClient = client; _rime = [GYRimeSession new];
    _candidatePanel = [[IMKCandidates alloc] initWithServer:server panelType:kIMKScrollingGridCandidatePanel];
    [_candidatePanel setDismissesAutomatically:NO];
    [_candidatePanel setAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold],
      NSForegroundColorAttributeName: [NSColor colorWithWhite:0.965 alpha:1],
      NSBackgroundColorDocumentAttribute: [NSColor colorWithRed:0.067 green:0.075 blue:0.094 alpha:1],
      IMKCandidatesSendServerKeyEventFirst: @YES}];
    GYTrace(_rime.ready ? @"controller-init rime=ready" : @"controller-init rime=failed");
  }
  return self;
}

- (void)activateServer:(id)sender { _activeClient = sender; GYTrace(@"controller-activate"); }
- (void)deactivateServer:(id)sender { (void)sender; [self clearComposition]; _activeClient = nil; GYTrace(@"controller-deactivate"); }
- (id)currentClient { return _activeClient ?: self.client; }

- (NSArray<NSString *> *)visibleCandidates {
  NSUInteger limit = _expanded ? 25 : 5;
  return [_rime.candidates subarrayWithRange:NSMakeRange(0, MIN(limit, _rime.candidates.count))];
}

- (void)showComposition {
  id client = self.currentClient;
  if (client && _rime.preedit.length) {
    [client setMarkedText:[[NSAttributedString alloc] initWithString:_rime.preedit]
            selectionRange:NSMakeRange(_rime.preedit.length, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
    _hasMarkedText = YES;
  }
}

- (void)refreshCandidates {
  NSArray *visible = self.visibleCandidates;
  if (visible.count == 0) { [_candidatePanel hide]; return; }
  _selection = MIN(_selection, (NSInteger)visible.count - 1);
  [_candidatePanel updateCandidates]; [_candidatePanel show:kIMKLocateCandidatesBelowHint];
  NSInteger identifier = [_candidatePanel candidateStringIdentifier:visible[(NSUInteger)_selection]];
  if (identifier != NSNotFound) [_candidatePanel selectCandidateWithIdentifier:identifier];
}

- (void)clearComposition {
  [_candidatePanel hide]; [_rime clear]; _selection = 0; _expanded = NO;
  id client = self.currentClient;
  if (_hasMarkedText && [client respondsToSelector:@selector(unmarkText)]) [client unmarkText];
  _hasMarkedText = NO;
}

- (void)applyRimeResult {
  NSString *commit = _rime.commitText;
  if (commit.length) { [self.currentClient insertText:commit replacementRange:NSMakeRange(NSNotFound, 0)]; [self clearComposition]; return; }
  if (_rime.preedit.length) { [self showComposition]; [self refreshCandidates]; } else [self clearComposition];
}

- (NSArray *)candidates:(id)sender { (void)sender; return self.visibleCandidates; }
- (id)composedString:(id)sender { (void)sender; return _rime.preedit; }
- (NSAttributedString *)originalString:(id)sender { (void)sender; return [[NSAttributedString alloc] initWithString:_rime.preedit]; }
- (void)commitComposition:(id)sender { (void)sender; [_rime commitDefault]; [self applyRimeResult]; }

- (void)candidateSelected:(NSAttributedString *)candidateString {
  NSInteger index = [self.visibleCandidates indexOfObject:candidateString.string];
  if (index != NSNotFound) { [_rime selectCandidateAtIndex:index]; [self applyRimeResult]; }
}

- (void)candidateSelectionChanged:(NSAttributedString *)candidateString {
  NSUInteger index = [self.visibleCandidates indexOfObject:candidateString.string];
  if (index != NSNotFound) _selection = (NSInteger)index;
}

- (BOOL)moveSelectionForKey:(NSInteger)keyCode {
  NSArray *visible = self.visibleCandidates;
  if (visible.count == 0) return NO;
  if (keyCode == kVK_DownArrow && !_expanded) { _expanded = YES; _selection = 0; [self refreshCandidates]; return YES; }
  if (keyCode == kVK_PageDown && [_rime nextPage]) { _selection = 0; [self refreshCandidates]; return YES; }
  if (keyCode == kVK_PageUp && [_rime previousPage]) { _selection = 0; [self refreshCandidates]; return YES; }
  if (keyCode == kVK_UpArrow && _selection < 5 && _expanded && !_rime.hasPreviousPage) { _expanded = NO; _selection = 0; [self refreshCandidates]; return YES; }
  NSInteger delta = keyCode == kVK_LeftArrow ? -1 : keyCode == kVK_RightArrow ? 1 : keyCode == kVK_UpArrow ? -5 : keyCode == kVK_DownArrow ? 5 : 0;
  NSInteger target = _selection + delta;
  if (delta == 0 || target < 0 || target >= (NSInteger)visible.count) return delta != 0;
  _selection = target; [self refreshCandidates]; return YES;
}

- (BOOL)selectNumberForKey:(NSInteger)keyCode {
  NSArray *keys = @[@(kVK_ANSI_1), @(kVK_ANSI_2), @(kVK_ANSI_3), @(kVK_ANSI_4), @(kVK_ANSI_5)];
  NSUInteger index = [keys indexOfObject:@(keyCode)];
  if (index == NSNotFound || index >= self.visibleCandidates.count) return NO;
  [_rime selectCandidateAtIndex:(NSInteger)index]; [self applyRimeResult]; return YES;
}

- (BOOL)inputText:(NSString *)string key:(NSInteger)keyCode modifiers:(NSUInteger)modifiers client:(id)client {
  _activeClient = client; GYTrace(@"text-event");
  NSEventModifierFlags blocked = NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagFunction;
  if ((modifiers & blocked) != 0) return NO;
  if ((keyCode == kVK_Shift || keyCode == kVK_RightShift) && string.length == 0) {
    GYInputMode mode = [GYInputModeStore.sharedStore cycleMode]; [self clearComposition];
    GYTrace([NSString stringWithFormat:@"mode=%@", GYInputModeLabel(mode)]); return YES;
  }
  if (!GYInputModeUsesChinese(GYInputModeStore.sharedStore.mode)) { if (_rime.preedit.length) [self clearComposition]; return NO; }
  if (keyCode == kVK_Escape && _rime.preedit.length) { [self clearComposition]; return YES; }
  if (keyCode == kVK_Delete) { if (![_rime deleteBackward]) return NO; [self applyRimeResult]; return YES; }
  if ([self moveSelectionForKey:keyCode] || [self selectNumberForKey:keyCode]) return YES;
  if ((keyCode == kVK_Space || keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter) && _rime.preedit.length) {
    [_rime selectCandidateAtIndex:_selection]; [self applyRimeResult]; return YES;
  }
  if ([_rime processText:string mode:GYInputModeStore.sharedStore.mode]) { [self applyRimeResult]; return YES; }
  if (_rime.preedit.length) { [_rime commitDefault]; [self applyRimeResult]; }
  return NO;
}

- (NSMenu *)menu {
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"GY 输入法"];
  for (NSNumber *value in @[@(GYInputModeSimplified), @(GYInputModeTraditional), @(GYInputModeEnglish)]) {
    GYInputMode mode = value.integerValue;
    NSMenuItem *item = [menu addItemWithTitle:GYInputModeLabel(mode) action:@selector(selectMode:) keyEquivalent:@""];
    item.representedObject = value; item.state = GYInputModeStore.sharedStore.mode == mode ? NSControlStateValueOn : NSControlStateValueOff;
  }
  return menu;
}

- (void)selectMode:(NSMenuItem *)item { [GYInputModeStore.sharedStore setMode:[(NSNumber *)item.representedObject integerValue]]; [self clearComposition]; }
- (void)inputControllerWillClose { [self clearComposition]; [super inputControllerWillClose]; }

@end
