#import <Foundation/Foundation.h>
#import "GYInputMode.h"

/// Persistent per-user settings shared by every IMK input session. Values live
/// in Application Support so a future Preferences app edits the same file.
@interface GYSettingsStore : NSObject

+ (instancetype)sharedStore;

@property(nonatomic) GYInputMode inputMode;
@property(nonatomic) GYInputMode lastChineseMode;
@property(nonatomic) NSInteger candidatePageSize;
@property(nonatomic) BOOL showExpandedCandidates;

- (NSDictionary<NSString *, NSString *> *)customPhrases;
- (void)setCustomPhrase:(NSString *)phrase forCode:(NSString *)code;
- (NSArray<NSString *> *)candidatesByAddingCustomPhrases:(NSArray<NSString *> *)rimeCandidates
                                                  forCode:(NSString *)code;

@end
