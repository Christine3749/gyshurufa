#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^GYCandidatePanelSelectionHandler)(NSUInteger index);
typedef void (^GYCandidatePanelActionHandler)(void);

// A lightweight, non-activating candidate strip.  It deliberately owns only
// presentation and pointer hit-testing; the IMK controller remains the single
// source of truth for composition, Rime state and keyboard selection.
@interface GYCandidatePanel : NSObject

- (instancetype)initWithSelectionHandler:(GYCandidatePanelSelectionHandler)selectionHandler
                         previousPageHandler:(GYCandidatePanelActionHandler)previousPageHandler
                             nextPageHandler:(GYCandidatePanelActionHandler)nextPageHandler
                         toggleExpandedHandler:(GYCandidatePanelActionHandler)toggleExpandedHandler
                        openSettingsHandler:(GYCandidatePanelActionHandler)openSettingsHandler;

- (void)showWithCandidates:(NSArray<NSString *> *)candidates
              selectedIndex:(NSUInteger)selectedIndex
                pageNumber:(NSUInteger)pageNumber
           canGoPreviousPage:(BOOL)canGoPreviousPage
               canGoNextPage:(BOOL)canGoNextPage
                   expanded:(BOOL)expanded
        canExpandCandidates:(BOOL)canExpandCandidates
                  inputModeTitle:(NSString *)inputModeTitle
                      forClient:(id)client;
// A short confirmation shown after a standalone Shift changes input mode.
// It mirrors the Windows Host's mode popup and is deliberately not a
// candidate row, so EN remains visible even when there is no composition.
- (void)showModeTitle:(NSString *)inputModeTitle forClient:(id)client;
- (void)hide;

@end

NS_ASSUME_NONNULL_END
