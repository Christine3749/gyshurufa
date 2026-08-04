#import "GYActivationEvidence.h"

void GYRecordInputRouteEvidence(void) {
  static NSUInteger eventCount = 0;
  if (++eventCount < 6) return;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSURL *support = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                             inDomains:NSUserDomainMask].firstObject;
    NSURL *directory = [support URLByAppendingPathComponent:@"GYInput" isDirectory:YES];
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
    if (![[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil]) return;
    NSURL *file = [directory URLByAppendingPathComponent:@"core-route.plist"];
    NSDictionary *record = @{ @"version": version, @"verifiedAt": [NSDate date] };
    [record writeToURL:file atomically:YES];
  });
}
