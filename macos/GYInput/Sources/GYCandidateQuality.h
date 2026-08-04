#import <Foundation/Foundation.h>
#import "GYInputMode.h"

FOUNDATION_EXPORT NSString *GYNormalizeCandidate(NSString *text, GYInputMode mode);
FOUNDATION_EXPORT BOOL GYCandidateIsTrusted(NSString *text, NSUInteger minimumLength, BOOL isPrimary);
