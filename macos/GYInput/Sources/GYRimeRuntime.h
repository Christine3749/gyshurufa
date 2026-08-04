#import <Foundation/Foundation.h>
#include "rime_api.h"

@interface GYRimeRuntime : NSObject

@property(nonatomic, readonly) RimeApi *api;
@property(nonatomic, readonly) BOOL ready;
@property(nonatomic, readonly) NSString *diagnostic;

+ (instancetype)sharedRuntime;

@end
