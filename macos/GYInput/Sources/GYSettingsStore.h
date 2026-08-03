#import <Foundation/Foundation.h>
#import "GYInputMode.h"

/// Persistent per-user settings shared by every IMK input session. Values live
/// in Application Support so a future Preferences app edits the same file.
@interface GYSettingsStore : NSObject

+ (instancetype)sharedStore;

@property(nonatomic) GYInputMode inputMode;
@property(nonatomic) GYInputMode lastChineseMode;
/// Candidate strip appearance shared with the Windows build:
/// 0 = GY 蓝夜, 1 = 暖白, 2 = 石墨.
@property(nonatomic) NSInteger candidateTheme;
/// Matches the Windows candidate-font range. The strip keeps its compact
/// height; only the candidate glyph size changes.
@property(nonatomic) NSInteger candidateFontSize;
@property(nonatomic) BOOL automaticUpdateChecks;
@property(nonatomic) NSTimeInterval lastUpdateCheckTimestamp;

- (NSDictionary<NSString *, NSString *> *)customPhrases;
- (void)setCustomPhrase:(NSString *)phrase forCode:(NSString *)code;
- (void)clearCustomPhrases;
- (NSArray<NSString *> *)candidatesByAddingCustomPhrases:(NSArray<NSString *> *)rimeCandidates
                                                  forCode:(NSString *)code;

/// A portable, privacy-preserving settings backup. Learning data and the
/// Rime user database are deliberately excluded.
- (NSDictionary<NSString *, id> *)portableSettingsBackup;
/// Validates and atomically applies a backup created by the method above.
- (BOOL)importPortableSettingsBackup:(NSDictionary<NSString *, id> *)backup
                                error:(NSError * _Nullable * _Nullable)error;

@end
