#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <InputMethodKit/InputMethodKit.h>
#import <string.h>
#import "GYRimeRuntime.h"
#import "GYUpdateService.h"

// TISRegisterInputSource only makes the system AWARE of the source (it shows
// up in System Settings > Keyboard > Input Sources > Edit…), it does NOT add
// it to the user's AppleEnabledInputSources — the list the live menu-bar
// switcher actually reads. Skipping the enable step is exactly why GY could
// be present in "Edit Input Sources…" yet completely absent from the input
// menu after a reinstall: registered but never enabled.
static int RegisterInputSource(void) {
  NSURL *bundleURL = NSBundle.mainBundle.bundleURL;
  if (bundleURL == nil || TISRegisterInputSource((__bridge CFURLRef)bundleURL) != noErr) return 1;

  NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
  if (bundleID.length == 0) return 1;

  NSDictionary *filter = @{(__bridge NSString *)kTISPropertyBundleID: bundleID};
  CFArrayRef sources = TISCreateInputSourceList((__bridge CFDictionaryRef)filter, true);
  if (sources == NULL) return 1;

  const CFIndex count = CFArrayGetCount(sources);
  BOOL enabledAny = NO;
  for (CFIndex i = 0; i < count; ++i) {
    TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(sources, i);
    if (TISEnableInputSource(source) == noErr) enabledAny = YES;
  }
  CFRelease(sources);
  return enabledAny ? 0 : 1;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc == 2 && strcmp(argv[1], "--register-input-source") == 0) return RegisterInputSource();
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
    GYRimeRuntime *runtime = GYRimeRuntime.sharedRuntime;
    [runtime start];
  [GYUpdateService.sharedService checkForUpdatesIfNeeded];
    [application run];
    (void)server;
    (void)runtime;
  }
  return 0;
}

