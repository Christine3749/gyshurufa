#import <Foundation/Foundation.h>
#import "GYInputMode.h"

@interface GYRimeSession : NSObject

@property(nonatomic, readonly) BOOL ready;
@property(nonatomic, readonly) NSString *preedit;
@property(nonatomic, readonly) NSArray<NSString *> *candidates;
@property(nonatomic, readonly) NSString *commitText;
@property(nonatomic, readonly) BOOL hasNextPage;
@property(nonatomic, readonly) BOOL hasPreviousPage;

- (BOOL)processText:(NSString *)text mode:(GYInputMode)mode;
- (BOOL)deleteBackward;
- (void)clear;
- (BOOL)nextPage;
- (BOOL)previousPage;
- (BOOL)selectCandidateAtIndex:(NSInteger)index;
- (BOOL)commitDefault;

@end

FOUNDATION_EXPORT BOOL GYRunRimeSelfTest(void);
