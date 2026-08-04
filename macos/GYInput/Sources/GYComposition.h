#import <Foundation/Foundation.h>
#import "GYInputMode.h"

@interface GYComposition : NSObject

@property(nonatomic, readonly) NSString *code;
@property(nonatomic, readonly) NSArray<NSString *> *visibleCandidates;
@property(nonatomic, readonly) BOOL expanded;

- (void)appendText:(NSString *)text mode:(GYInputMode)mode;
- (BOOL)deleteBackward;
- (void)clear;
- (void)expand;
- (void)collapse;
- (BOOL)nextPage;
- (BOOL)previousPage;
- (NSString *)candidateAtVisibleIndex:(NSInteger)index;
- (void)learnCandidate:(NSString *)candidate;

@end

FOUNDATION_EXPORT BOOL GYRunInputCoreSelfTest(void);
