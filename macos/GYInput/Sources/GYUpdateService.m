#import "GYUpdateService.h"
#import "GYSettingsStore.h"

static NSTimeInterval const GYUpdateCheckInterval = 24.0 * 60.0 * 60.0;
static NSURL *GYUpdateManifestURL(void) {
  return [NSURL URLWithString:@"https://www.shurufa.wang/download/latest-macos.json"];
}

@implementation GYUpdateService

+ (instancetype)sharedService {
  static GYUpdateService *service;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ service = [[self alloc] initPrivate]; });
  return service;
}

- (instancetype)init { return [GYUpdateService sharedService]; }
- (instancetype)initPrivate { return [super init]; }

- (void)finish:(GYUpdateCheckCompletion)completion status:(NSString *)status packageURL:(NSURL *)packageURL {
  if (completion == nil) return;
  dispatch_async(dispatch_get_main_queue(), ^{ completion(status, packageURL); });
}

- (void)checkForUpdatesIfNeeded {
  GYSettingsStore *settings = GYSettingsStore.sharedStore;
  if (!settings.automaticUpdateChecks) return;
  NSTimeInterval now = NSDate.date.timeIntervalSince1970;
  if (now - settings.lastUpdateCheckTimestamp < GYUpdateCheckInterval) return;
  settings.lastUpdateCheckTimestamp = now;
  [self checkForUpdatesWithCompletion:nil];
}

- (void)checkForUpdatesWithCompletion:(GYUpdateCheckCompletion)completion {
  NSURL *manifestURL = GYUpdateManifestURL();
  if (manifestURL == nil) {
    [self finish:completion status:@"更新地址无效。" packageURL:nil];
    return;
  }
  GYSettingsStore.sharedStore.lastUpdateCheckTimestamp = NSDate.date.timeIntervalSince1970;
  NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
  configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  configuration.timeoutIntervalForRequest = 12.0;
  NSURLSessionDataTask *task = [[NSURLSession sessionWithConfiguration:configuration]
      dataTaskWithURL:manifestURL
    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
      if (error != nil || http.statusCode != 200 || data.length == 0) {
        [self finish:completion status:@"暂时无法连接更新服务器。" packageURL:nil];
        return;
      }
      id decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
      if (![decoded isKindOfClass:NSDictionary.class]) {
        [self finish:completion status:@"更新信息格式无效，未执行任何下载。" packageURL:nil];
        return;
      }
      NSDictionary *manifest = decoded;
      NSString *version = [manifest[@"version"] isKindOfClass:NSString.class] ? manifest[@"version"] : nil;
      NSNumber *build = [manifest[@"build"] isKindOfClass:NSNumber.class] ? manifest[@"build"] : nil;
      NSString *urlText = [manifest[@"packageURL"] isKindOfClass:NSString.class] ? manifest[@"packageURL"] : nil;
      NSString *sha256 = [manifest[@"sha256"] isKindOfClass:NSString.class] ? manifest[@"sha256"] : nil;
      NSURL *packageURL = [NSURL URLWithString:urlText ?: @""];
      NSString *host = packageURL.host.lowercaseString;
      BOOL officialHost = [host isEqualToString:@"shurufa.wang"] || [host isEqualToString:@"www.shurufa.wang"];
      NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
      BOOL validChecksum = sha256.length == 64 && [sha256 rangeOfCharacterFromSet:hex.invertedSet].location == NSNotFound;
      if (version.length == 0 || build == nil || packageURL == nil || ![packageURL.scheme.lowercaseString isEqualToString:@"https"] ||
          !officialHost || !validChecksum) {
        [self finish:completion status:@"更新信息未通过安全校验，未执行任何下载。" packageURL:nil];
        return;
      }
      id currentBuildValue = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
      NSInteger currentBuild = [currentBuildValue respondsToSelector:@selector(integerValue)] ? [currentBuildValue integerValue] : 0;
      if (build.integerValue <= currentBuild) {
        [self finish:completion status:[NSString stringWithFormat:@"已是最新版本（%@）。", version] packageURL:nil];
        return;
      }
      [self finish:completion
             status:[NSString stringWithFormat:@"发现新版本 %@。下载后需要 macOS 管理员授权安装。", version]
         packageURL:packageURL];
    }];
  [task resume];
}

@end
