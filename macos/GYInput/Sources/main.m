#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <InputMethodKit/InputMethodKit.h>
#import "GYCandidatePanel.h"
#import "GYRimeSession.h"
#import <string.h>

static int RegisterInputSource(void) {
  NSURL *bundleURL = NSBundle.mainBundle.bundleURL;
  if (bundleURL == nil || TISRegisterInputSource((__bridge CFURLRef)bundleURL) != noErr) return 1;
  NSString *modeID = [NSBundle.mainBundle.bundleIdentifier stringByAppendingString:@".pinyin"];
  NSDictionary *filter = @{(__bridge NSString *)kTISPropertyInputSourceID: modeID};
  // A newly registered source is disabled. Include disabled sources here so
  // this first-run path can find and enable the new mode.
  CFArrayRef sources = TISCreateInputSourceList((__bridge CFDictionaryRef)filter, true);
  if (sources == nil || CFArrayGetCount(sources) != 1) { if (sources) CFRelease(sources); return 2; }
  TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(sources, 0);
  OSStatus status = TISEnableInputSource(source); CFRelease(sources);
  return status == noErr ? 0 : 3;
}

static int PreviewCandidates(BOOL expanded) {
  NSApplication *application = NSApplication.sharedApplication;
  application.activationPolicy = NSApplicationActivationPolicyRegular;
  NSArray *words = @[@"你好", @"您好", @"你们", @"拟好", @"泥好", @"你好啊", @"你好吗", @"你好呀", @"你好看", @"你好像", @"你好棒", @"你好么", @"你很好", @"你好吧", @"你好啦", @"你好呢", @"你好哦", @"你好喔", @"你好朋友", @"你好同学", @"你好老师", @"你好大家", @"你好中国", @"你好生活", @"你好未来"];
  GYCandidatePanel *panel = [[GYCandidatePanel alloc] initWithActionHandler:^(GYCandidateAction action, NSInteger index) {
    NSLog(@"GY preview action=%ld index=%ld", (long)action, (long)index);
  }];
  [panel showCandidates:expanded ? words : [words subarrayWithRange:NSMakeRange(0, 5)] selection:0
                   mode:GYInputModeSimplified expanded:expanded expandable:YES previous:NO next:expanded client:nil];
  [application activateIgnoringOtherApps:YES]; [application run];
  return 0;
}

static int DumpCandidates(const char *code) {
  GYRimeSession *session = [GYRimeSession new];
  NSString *input = [NSString stringWithUTF8String:code] ?: @"";
  if (!session.ready || ![session processText:input mode:GYInputModeSimplified]) return 1;
  for (NSString *candidate in session.candidates) {
    printf("%s\n", candidate.UTF8String);
  }
  return session.candidates.count ? 0 : 1;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc == 2 && strcmp(argv[1], "--register-input-source") == 0) return RegisterInputSource();
    if (argc == 2 && strcmp(argv[1], "--self-test") == 0) return GYRunRimeSelfTest() ? 0 : 1;
    if (argc == 2 && strcmp(argv[1], "--preview-collapsed") == 0) return PreviewCandidates(NO);
    if (argc == 2 && strcmp(argv[1], "--preview-expanded") == 0) return PreviewCandidates(YES);
    if (argc == 3 && strcmp(argv[1], "--dump-candidates") == 0) return DumpCandidates(argv[2]);
    if (argc != 1) return 64;

    NSBundle *bundle = NSBundle.mainBundle;
    NSString *connection = [bundle objectForInfoDictionaryKey:@"InputMethodConnectionName"];
    if (bundle.bundleIdentifier.length == 0 || connection.length == 0) return 65;
    // InputMethodKit requires exactly one IMKServer. Compatibility comes from
    // keeping the registered connection name stable, never from a second
    // legacy endpoint in the same process.
    IMKServer *server = [[IMKServer alloc] initWithName:connection bundleIdentifier:bundle.bundleIdentifier];
    if (server == nil) return 2;
    NSLog(@"GY core: IMKServer ready");

    NSApplication *application = NSApplication.sharedApplication;
    [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [application run];
    (void)server;
  }
  return 0;
}
