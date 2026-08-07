#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <InputMethodKit/InputMethodKit.h>
#import <string.h>
#import "GYRimeRuntime.h"
#import "GYUpdateService.h"

static int RegisterInputSource(void) {
  NSURL *bundleURL = NSBundle.mainBundle.bundleURL;
  return bundleURL != nil && TISRegisterInputSource((__bridge CFURLRef)bundleURL) == noErr ? 0 : 1;
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

