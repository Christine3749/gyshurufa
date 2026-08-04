#import <Carbon/Carbon.h>
#import <InputMethodKit/InputMethodKit.h>
#import "GYActivationEvidence.h"
#import "GYDiagnostics.h"
#import "GYCandidatePanel.h"
#import "GYInputMode.h"
#import "GYRimeSession.h"

static const NSUInteger GYCandidatePoolLimit = 75;
static const NSUInteger GYCandidatesPerPage = 25;

@interface GYInputController : IMKInputController
@end

@implementation GYInputController {
  __weak id _activeClient;
  GYRimeSession *_rime;
  GYCandidatePanel *_candidatePanel;
  NSInteger _selection;
  NSUInteger _candidatePage;
  BOOL _expanded;
  BOOL _hasMarkedText;
}

- (instancetype)initWithServer:(IMKServer *)server delegate:(id)delegate client:(id)client {
  self = [super initWithServer:server delegate:delegate client:client];
  if (self) {
    _activeClient = client; _rime = [GYRimeSession new];
    __weak GYInputController *weakSelf = self;
    _candidatePanel = [[GYCandidatePanel alloc] initWithActionHandler:^(GYCandidateAction action, NSInteger index) {
      GYInputController *strongSelf = weakSelf; if (!strongSelf) return;
      if (action == GYCandidateActionSelect) {
        [strongSelf selectVisibleCandidateAtIndex:index]; [strongSelf applyRimeResult]; return;
      }
      if (action == GYCandidateActionToggle) { strongSelf->_expanded = !strongSelf->_expanded; strongSelf->_candidatePage = 0; }
      else if (action == GYCandidateActionPrevious) [strongSelf previousCandidatePage];
      else if (action == GYCandidateActionNext) [strongSelf nextCandidatePage];
      strongSelf->_selection = 0; [strongSelf refreshCandidates];
    }];
    GYTrace(_rime.ready ? @"controller-init rime=ready" : @"controller-init rime=failed");
  }
  return self;
}

- (void)activateServer:(id)sender { _activeClient = sender; GYTrace(@"controller-activate"); }
- (void)deactivateServer:(id)sender { (void)sender; [self clearComposition]; _activeClient = nil; GYTrace(@"controller-deactivate"); }
- (id)currentClient { return _activeClient ?: self.client; }

- (NSUInteger)candidateCount { return MIN(GYCandidatePoolLimit, _rime.candidates.count); }
- (NSUInteger)candidateOffset { return _expanded ? _candidatePage * GYCandidatesPerPage : 0; }
- (void)normalizeCandidatePage {
  if (!_expanded || self.candidateCount == 0) { _candidatePage = 0; return; }
  _candidatePage = MIN(_candidatePage, (self.candidateCount - 1) / GYCandidatesPerPage);
}
- (NSArray<NSString *> *)visibleCandidates {
  [self normalizeCandidatePage]; NSUInteger offset = self.candidateOffset;
  NSUInteger limit = _expanded ? GYCandidatesPerPage : 5;
  NSUInteger length = MIN(limit, self.candidateCount - offset);
  return [_rime.candidates subarrayWithRange:NSMakeRange(offset, length)];
}
- (BOOL)hasNextCandidatePage {
  return _expanded && self.candidateOffset + GYCandidatesPerPage < self.candidateCount;
}
- (BOOL)nextCandidatePage {
  if (![self hasNextCandidatePage]) return NO;
  _candidatePage++; _selection = 0; return YES;
}
- (BOOL)previousCandidatePage {
  if (!_expanded || _candidatePage == 0) return NO;
  _candidatePage--; _selection = 0; return YES;
}
- (BOOL)selectVisibleCandidateAtIndex:(NSInteger)index {
  NSInteger absoluteIndex = (NSInteger)self.candidateOffset + index;
  if (index < 0 || absoluteIndex >= (NSInteger)self.candidateCount) return NO;
  return [_rime selectCandidateAtIndex:absoluteIndex];
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
  [_candidatePanel showCandidates:visible selection:_selection mode:GYInputModeStore.sharedStore.mode expanded:_expanded
                       expandable:self.candidateCount > 5 previous:_candidatePage > 0
                             next:self.hasNextCandidatePage client:self.currentClient];
}

- (void)clearComposition {
  [_candidatePanel hide]; [_rime clear]; _selection = 0; _candidatePage = 0; _expanded = NO;
  id client = self.currentClient;
  if (_hasMarkedText && [client respondsToSelector:@selector(unmarkText)]) [client unmarkText];
  _hasMarkedText = NO;
}

- (void)applyRimeResult {
  NSString *commit = _rime.commitText;
  if (commit.length) { [self.currentClient insertText:commit replacementRange:NSMakeRange(NSNotFound, 0)]; [self clearComposition]; return; }
  if (_rime.preedit.length) { [self showComposition]; [self refreshCandidates]; } else [self clearComposition];
}

- (id)composedString:(id)sender { (void)sender; return _rime.preedit; }
- (NSAttributedString *)originalString:(id)sender { (void)sender; return [[NSAttributedString alloc] initWithString:_rime.preedit]; }
- (void)commitComposition:(id)sender { (void)sender; [_rime commitDefault]; [self applyRimeResult]; }

- (BOOL)moveSelectionForKey:(NSInteger)keyCode {
  NSArray *visible = self.visibleCandidates;
  if (visible.count == 0) return NO;
  if (keyCode == kVK_DownArrow && !_expanded && self.candidateCount > 5) { _expanded = YES; _selection = 0; [self refreshCandidates]; return YES; }
  if (keyCode == kVK_PageDown && _expanded) { if ([self nextCandidatePage]) [self refreshCandidates]; return YES; }
  if (keyCode == kVK_PageUp && _expanded) { if ([self previousCandidatePage]) [self refreshCandidates]; return YES; }
  if (keyCode == kVK_UpArrow && _selection < 5 && _expanded) {
    NSInteger column = _selection;
    if ([self previousCandidatePage]) {
      NSArray *previous = self.visibleCandidates; NSInteger rowStart = MAX(0, (NSInteger)previous.count - 5) / 5 * 5;
      _selection = MIN(rowStart + column, (NSInteger)previous.count - 1); [self refreshCandidates]; return YES;
    }
    _expanded = NO; _selection = 0; [self refreshCandidates]; return YES;
  }
  NSInteger delta = keyCode == kVK_LeftArrow ? -1 : keyCode == kVK_RightArrow ? 1 : keyCode == kVK_UpArrow ? -5 : keyCode == kVK_DownArrow ? 5 : 0;
  NSInteger target = _selection + delta;
  if (delta == 0 || target < 0 || target >= (NSInteger)visible.count) {
    if (_expanded && keyCode == kVK_DownArrow && [self nextCandidatePage]) {
      NSArray *next = self.visibleCandidates; _selection = MIN(_selection % 5, (NSInteger)next.count - 1); [self refreshCandidates]; return YES;
    }
    return delta != 0;
  }
  _selection = target; [self refreshCandidates]; return YES;
}

- (BOOL)selectNumberForKey:(NSInteger)keyCode {
  NSArray *keys = @[@(kVK_ANSI_1), @(kVK_ANSI_2), @(kVK_ANSI_3), @(kVK_ANSI_4), @(kVK_ANSI_5)];
  NSUInteger index = [keys indexOfObject:@(keyCode)];
  if (index == NSNotFound || index >= self.visibleCandidates.count) return NO;
  [self selectVisibleCandidateAtIndex:(NSInteger)index]; [self applyRimeResult]; return YES;
}

- (BOOL)inputText:(NSString *)string key:(NSInteger)keyCode modifiers:(NSUInteger)modifiers client:(id)client {
  _activeClient = client; GYTrace(@"text-event"); GYRecordInputRouteEvidence();
  NSEventModifierFlags blocked = NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagFunction;
  if ((modifiers & blocked) != 0) return NO;
  if (!GYInputModeUsesChinese(GYInputModeStore.sharedStore.mode)) { if (_rime.preedit.length) [self clearComposition]; return NO; }
  if (keyCode == kVK_Escape && _rime.preedit.length) { [self clearComposition]; return YES; }
  if (keyCode == kVK_Delete) { if (![_rime deleteBackward]) return NO; [self applyRimeResult]; return YES; }
  if ([self moveSelectionForKey:keyCode] || [self selectNumberForKey:keyCode]) return YES;
  if ((keyCode == kVK_Space || keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter) && _rime.preedit.length) {
    [self selectVisibleCandidateAtIndex:_selection]; [self applyRimeResult]; return YES;
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
    item.target = self; item.representedObject = value; item.state = GYInputModeStore.sharedStore.mode == mode ? NSControlStateValueOn : NSControlStateValueOff;
  }
  return menu;
}

- (void)selectMode:(NSMenuItem *)item {
  GYInputMode mode = [(NSNumber *)item.representedObject integerValue];
  [GYInputModeStore.sharedStore setMode:mode]; [self clearComposition];
  GYTrace([NSString stringWithFormat:@"mode=%@", GYInputModeLabel(mode)]);
}
- (void)inputControllerWillClose { [self clearComposition]; [super inputControllerWillClose]; }

@end
