#import <Cocoa/Cocoa.h>
#import <InputMethodKit/InputMethodKit.h>

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *name = [bundle objectForInfoDictionaryKey:@"InputMethodConnectionName"];
    NSString *bundleIdentifier = bundle.bundleIdentifier;
    if (name.length == 0 || bundleIdentifier.length == 0) return 2;

    // IMKServer reads the controller class from the input-method bundle Info.plist.
    IMKServer *server = [[IMKServer alloc] initWithName:name bundleIdentifier:bundleIdentifier];
    if (server == nil) return 3;

    [NSApplication sharedApplication];
    [NSApp run];
  }
  return 0;
}
