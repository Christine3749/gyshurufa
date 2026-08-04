#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// GY custom candidate window. Pixel-faithful macOS port of the locked
/// Windows contract in native/src/CandidateWindow.cpp:
/// collapsed strip of 5 chips → disclosure ˅ → divider → 简/繁/EN;
/// expanded fixed 5×5 grid with ˄ + mode label + pager in the bottom bar.
@interface GYCandidateWindow : NSObject

/// choose: absolute index into the candidates array passed to showAtCaret:.
/// disclosure: user clicked ˅/˄; parameter is the NEW expanded state.
/// page: -1 previous page, +1 next page (local pagination within the array).
/// settings: user clicked the mode label.
- (instancetype)initWithChooseHandler:(void (^)(NSUInteger absoluteIndex))choose
                   disclosureHandler:(void (^)(BOOL expanded))disclosure
                         pageHandler:(void (^)(NSInteger direction))page
                     settingsHandler:(void (^)(void))settings;

/// caret: screen coordinates (bottom-left origin) of the input caret, as
/// returned by IMK -attributesForCharacterIndex:lineHeightRectangle:.
- (void)showAtCaret:(NSRect)caret
         candidates:(NSArray<NSString *> *)candidates
           selected:(NSUInteger)selected
          pageStart:(NSUInteger)pageStart
           expanded:(BOOL)expanded
          inputMode:(NSInteger)inputMode; // 0 简, 1 繁, 2 EN

/// Compact mode-only popup that hides itself after 700ms (Windows ShowMode).
- (void)showModeAtCaret:(NSRect)caret inputMode:(NSInteger)inputMode;

- (void)hide;

@end

NS_ASSUME_NONNULL_END
