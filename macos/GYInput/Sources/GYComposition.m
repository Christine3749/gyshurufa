#import "GYComposition.h"
#import "GYLexicon.h"
#import "GYLearningStore.h"

@implementation GYComposition {
  NSMutableString *_code;
  NSArray<NSString *> *_candidates;
  NSUInteger _page;
  BOOL _expanded;
  GYInputMode _mode;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _code = [NSMutableString string];
    _candidates = @[];
  }
  return self;
}

- (NSString *)code { return _code; }
- (BOOL)expanded { return _expanded; }

- (NSArray<NSString *> *)visibleCandidates {
  NSUInteger start = _expanded ? _page * 25 : 0;
  NSUInteger maximum = _expanded ? 25 : 5;
  if (start >= _candidates.count) return @[];
  NSUInteger length = MIN(maximum, _candidates.count - start);
  return [_candidates subarrayWithRange:NSMakeRange(start, length)];
}

- (void)appendText:(NSString *)text mode:(GYInputMode)mode {
  NSString *normalized = [GYLexicon normalizedCode:text];
  if (normalized.length == 0) return;
  [_code appendString:normalized];
  _mode = mode;
  _candidates = [[GYLearningStore sharedStore] rankedCandidates:[GYLexicon candidatesForCode:_code mode:mode] forCode:_code];
  _page = 0;
  _expanded = NO;
}

- (BOOL)deleteBackward {
  if (_code.length == 0) return NO;
  [_code deleteCharactersInRange:NSMakeRange(_code.length - 1, 1)];
  _candidates = [[GYLearningStore sharedStore] rankedCandidates:[GYLexicon candidatesForCode:_code mode:_mode] forCode:_code];
  _page = 0;
  _expanded = NO;
  return YES;
}

- (void)clear {
  [_code setString:@""];
  _candidates = @[];
  _page = 0;
  _expanded = NO;
}

- (void)expand { _expanded = YES; }
- (void)collapse { _expanded = NO; _page = 0; }

- (BOOL)nextPage {
  if (!_expanded || (_page + 1) * 25 >= _candidates.count) return NO;
  _page++;
  return YES;
}

- (BOOL)previousPage {
  if (!_expanded || _page == 0) return NO;
  _page--;
  return YES;
}

- (NSString *)candidateAtVisibleIndex:(NSInteger)index {
  NSArray<NSString *> *visible = self.visibleCandidates;
  return index >= 0 && (NSUInteger)index < visible.count ? visible[(NSUInteger)index] : nil;
}

- (void)learnCandidate:(NSString *)candidate {
  if ([_candidates containsObject:candidate]) [[GYLearningStore sharedStore] recordCandidate:candidate forCode:_code];
}

@end

BOOL GYRunInputCoreSelfTest(void) {
  GYComposition *composition = [GYComposition new];
  [composition appendText:@"nihao" mode:GYInputModeSimplified];
  if (![composition.visibleCandidates containsObject:@"你好"]) return NO;
  [composition clear];
  [composition appendText:@"zhongguo" mode:GYInputModeTraditional];
  if (![composition.visibleCandidates containsObject:@"中國"]) return NO;
  if ([GYLexicon candidatesForCode:@"zhongguo" mode:GYInputModeEnglish].count != 0) return NO;
  [composition expand];
  if (composition.visibleCandidates.count == 0 || [composition nextPage]) return NO;
  [composition deleteBackward];
  return composition.code.length == 7 && !composition.expanded;
}
