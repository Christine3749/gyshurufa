#import "GYDiagnostics.h"
#import <fcntl.h>
#import <unistd.h>

void GYTrace(NSString *event) {
  static int handle = -1;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSString *folder = [NSBundle.mainBundle objectForInfoDictionaryKey:@"GYApplicationSupportFolder"] ?: @"GYInput";
    NSString *path = [@"/tmp/" stringByAppendingFormat:@"%@-core.trace", folder];
    handle = open(path.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT, 0600);
    if (handle < 0) return;
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *build = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown";
    NSString *identifier = bundle.bundleIdentifier ?: @"unknown";
    dprintf(handle, "pid=%d build=%s route=inputText:key:modifiers:client: bundle=%s\n",
            getpid(), build.UTF8String, identifier.UTF8String);
  });
  if (handle >= 0) dprintf(handle, "%s\n", event.UTF8String);
}
