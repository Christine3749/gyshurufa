#import <Foundation/Foundation.h>
#import "GYInputMode.h"

@interface GYLexicon : NSObject

+ (NSArray<NSString *> *)candidatesForCode:(NSString *)code mode:(GYInputMode)mode;
+ (NSString *)normalizedCode:(NSString *)text;

@end
