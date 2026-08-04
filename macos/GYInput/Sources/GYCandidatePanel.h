#import <Cocoa/Cocoa.h>
#import "GYInputMode.h"

typedef NS_ENUM(NSInteger, GYCandidateAction) {
  GYCandidateActionSelect, GYCandidateActionToggle, GYCandidateActionPrevious, GYCandidateActionNext,
};
typedef void (^GYCandidateActionHandler)(GYCandidateAction action, NSInteger index);

@interface GYCandidatePanel : NSObject
- (instancetype)initWithActionHandler:(GYCandidateActionHandler)handler;
- (void)showCandidates:(NSArray<NSString *> *)candidates selection:(NSInteger)selection
                  mode:(GYInputMode)mode expanded:(BOOL)expanded expandable:(BOOL)expandable
              previous:(BOOL)previous next:(BOOL)next client:(id)client;
- (void)hide;
@end
