#import "GYPreferencesController.h"
#import "GYInputMode.h"
#import "GYSettingsStore.h"

@implementation GYPreferencesController

+ (instancetype)sharedController {
  static GYPreferencesController *controller;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ controller = [[self alloc] init]; });
  return controller;
}

- (void)show {
  GYSettingsStore *store = GYSettingsStore.sharedStore;
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"GY 输入法设置";
  alert.informativeText = @"输入和学习数据仅保存在本机。";
  [alert addButtonWithTitle:@"保存"];
  [alert addButtonWithTitle:@"取消"];

  NSSegmentedControl *modes = [[NSSegmentedControl alloc] initWithLabels:@[@"简体", @"繁体", @"EN"]
                                                              trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                    target:nil
                                                                    action:nil];
  modes.selectedSegment = store.inputMode;
  modes.translatesAutoresizingMaskIntoConstraints = NO;

  NSTextField *code = [NSTextField textFieldWithString:@""];
  code.placeholderString = @"短语编码，例如：dz";
  NSTextField *phrase = [NSTextField textFieldWithString:@""];
  phrase.placeholderString = @"短语内容，例如：我的电子邮箱";
  NSStackView *stack = [NSStackView stackViewWithViews:@[
      [NSTextField labelWithString:@"输入模式"], modes,
      [NSTextField labelWithString:@"新增本地短语（可留空）"], code, phrase,
      [NSTextField labelWithString:@"Shift 切换中文／EN；回车原样提交拼音。"]
  ]];
  stack.orientation =NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading;
  stack.spacing = 8.0;
  stack.edgeInsets = NSEdgeInsetsMake(4, 0, 4, 0);
  stack.frame = NSMakeRect(0, 0, 360, 180);
  alert.accessoryView = stack;

  if ([alert runModal] != NSAlertFirstButtonReturn) return;
  GYInputMode mode = (GYInputMode)modes.selectedSegment;
  store.inputMode = mode;
  NSString *shortCode = code.stringValue.lowercaseString;
  NSString *shortPhrase = phrase.stringValue;
  if (shortCode.length != 0 || shortPhrase.length != 0) {
    if (shortCode.length == 0 || shortPhrase.length == 0) {
      NSBeep();
      return;
    }
    [store setCustomPhrase:shortPhrase forCode:shortCode];
  }
}

@end
