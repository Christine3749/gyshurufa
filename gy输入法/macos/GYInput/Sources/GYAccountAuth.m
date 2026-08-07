#import "GYAccountAuth.h"
#import <Security/Security.h>

NSString *const GYAccountAuthDidChangeNotification = @"GYAccountAuthDidChangeNotification";

static NSString *const kAuthBase = @"https://gsyen-api-776196228503.asia-east1.run.app";
static NSString *const kKeychainService = @"wang.shurufa.GYInput.gsyen";
static NSString *const kKeychainAccount = @"session";
static const NSTimeInterval kRequestTimeout = 15;
// Refresh a little before the real expiry so a sync round never starts with a
// token that dies mid-flight.
static const NSTimeInterval kExpiryGuard = 60;

// MARK: - Keychain (refresh token only; never the password)

static BOOL GYKeychainStore(NSString *email, NSString *refreshToken) {
  NSDictionary *blob = @{@"email": email ?: @"", @"refresh_token": refreshToken ?: @""};
  NSData *data = [NSJSONSerialization dataWithJSONObject:blob options:0 error:nil];
  if (data == nil) return NO;
  NSDictionary *query = @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService: kKeychainService,
    (__bridge id)kSecAttrAccount: kKeychainAccount,
  };
  SecItemDelete((__bridge CFDictionaryRef)query);
  NSMutableDictionary *item = [query mutableCopy];
  item[(__bridge id)kSecValueData] = data;
  item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
  return SecItemAdd((__bridge CFDictionaryRef)item, NULL) == errSecSuccess;
}

static NSDictionary *_Nullable GYKeychainLoad(void) {
  NSDictionary *query = @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService: kKeychainService,
    (__bridge id)kSecAttrAccount: kKeychainAccount,
    (__bridge id)kSecReturnData: @YES,
    (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
  };
  CFTypeRef result = NULL;
  if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess) return nil;
  NSData *data = CFBridgingRelease(result);
  id parsed = data == nil ? nil : [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  return [parsed isKindOfClass:NSDictionary.class] ? parsed : nil;
}

static void GYKeychainDelete(void) {
  NSDictionary *query = @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService: kKeychainService,
    (__bridge id)kSecAttrAccount: kKeychainAccount,
  };
  SecItemDelete((__bridge CFDictionaryRef)query);
}

// MARK: - Response shape

/// Accepts both a bare session object and one wrapped in the standard
/// `{ ok, data: { … } }` envelope.
static NSDictionary *_Nullable GYSessionPayload(id json) {
  if (![json isKindOfClass:NSDictionary.class]) return nil;
  NSDictionary *root = json;
  if (root[@"access_token"] == nil && [root[@"data"] isKindOfClass:NSDictionary.class]) {
    root = root[@"data"];
  }
  return root[@"access_token"] != nil ? root : nil;
}

static NSString *_Nullable GYStringValue(id value) {
  return [value isKindOfClass:NSString.class] && ((NSString *)value).length != 0 ? value : nil;
}

@implementation GYAccountAuth {
  NSLock *_lock;
  dispatch_queue_t _queue;
  NSURLSession *_session;
  GYAccountStatus _status;
  NSString *_email;
  NSString *_refreshToken;
  NSString *_accessToken;
  NSTimeInterval _accessTokenExpiry;
  BOOL _refreshing;
  NSMutableArray<void (^)(NSString *_Nullable)> *_pendingTokenCompletions;
}

+ (instancetype)sharedAuth {
  static GYAccountAuth *auth;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ auth = [[self alloc] initPrivate]; });
  return auth;
}

- (instancetype)init { return [GYAccountAuth sharedAuth]; }

- (instancetype)initPrivate {
  self = [super init];
  if (!self) return nil;
  _lock = [[NSLock alloc] init];
  _queue = dispatch_queue_create("wang.shurufa.GYInput.auth", DISPATCH_QUEUE_SERIAL);
  _pendingTokenCompletions = [NSMutableArray array];
  _status = GYAccountStatusLoggedOut;
  _email = @"";
  NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
  // The refresh cookie is set by hand on the one request that needs it; a
  // native client must not inherit or persist a shared cookie jar.
  configuration.HTTPShouldSetCookies = NO;
  configuration.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
  configuration.timeoutIntervalForRequest = kRequestTimeout;
  _session = [NSURLSession sessionWithConfiguration:configuration];
  return self;
}

// MARK: - Observable state

- (GYAccountStatus)status {
  [_lock lock];
  const GYAccountStatus status = _status;
  [_lock unlock];
  return status;
}

- (NSString *)email {
  [_lock lock];
  NSString *email = [_email copy];
  [_lock unlock];
  return email;
}

- (void)setStatus:(GYAccountStatus)status email:(NSString *_Nullable)email {
  [_lock lock];
  const BOOL changed = _status != status || (email != nil && ![_email isEqualToString:email]);
  _status = status;
  if (email != nil) _email = [email copy];
  [_lock unlock];
  if (!changed) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    [NSNotificationCenter.defaultCenter postNotificationName:GYAccountAuthDidChangeNotification object:self];
  });
}

- (void)restoreSessionIfNeeded {
  [_lock lock];
  const BOOL alreadyKnown = _refreshToken != nil;
  [_lock unlock];
  if (alreadyKnown) return;
  NSDictionary *stored = GYKeychainLoad();
  NSString *refreshToken = GYStringValue(stored[@"refresh_token"]);
  if (refreshToken == nil) return;
  [_lock lock];
  _refreshToken = refreshToken;
  [_lock unlock];
  // Optimistic: the first refresh confirms it, and a 401 there signs us out.
  [self setStatus:GYAccountStatusLoggedIn email:GYStringValue(stored[@"email"]) ?: @""];
}

// MARK: - Login

- (void)loginWithEmail:(NSString *)email
              password:(NSString *)password
            completion:(void (^)(BOOL, NSString *_Nullable))completion {
  NSString *trimmed = [(email ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  void (^finish)(BOOL, NSString *_Nullable) = ^(BOOL success, NSString *_Nullable message) {
    if (completion == nil) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(success, message); });
  };
  if (trimmed.length == 0 || password.length == 0) {
    // 诊断用，不含任何凭据内容：如果这条出现而用户明明填了，
    // 说明读取时机不对（文本框还没结束编辑），而不是用户没填。
    NSLog(@"GY account: login aborted before any request — empty email=%d password=%d",
          trimmed.length == 0, password.length == 0);
    [self setStatus:GYAccountStatusFailed email:nil];
    finish(NO, @"请输入邮箱和密码。");
    return;
  }
  [self setStatus:GYAccountStatusLoggingIn email:nil];

  NSMutableURLRequest *request = [self requestForPath:@"/api/auth/login" method:@"POST"];
  request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"email": trimmed, @"password": password}
                                                     options:0
                                                       error:nil];
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

  __weak typeof(self) weakSelf = self;
  [[_session dataTaskWithRequest:request
               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                 typeof(self) self_ = weakSelf;
                 if (self_ == nil) return;
                 if (error != nil) {
                   NSLog(@"GY account: login transport error (NSURLError %ld)", (long)error.code);
                   [self_ setStatus:GYAccountStatusFailed email:nil];
                   finish(NO, @"网络连接失败，请稍后再试。");
                   return;
                 }
                 const NSInteger code = ((NSHTTPURLResponse *)response).statusCode;
                 NSDictionary *payload = GYSessionPayload(data == nil ? nil : [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]);
                 NSString *accessToken = GYStringValue(payload[@"access_token"]);
                 NSString *refreshToken = GYStringValue(payload[@"refresh_token"]);
                 if (code < 200 || code > 299 || accessToken == nil || refreshToken == nil) {
                   NSLog(@"GY account: login rejected (HTTP %ld, access_token=%d refresh_token=%d)",
                         (long)code, accessToken != nil, refreshToken != nil);
                   [self_ setStatus:GYAccountStatusFailed email:nil];
                   finish(NO, code == 401 || code == 400 ? @"邮箱或密码不正确。" : @"登录失败，请稍后再试。");
                   return;
                 }
                 NSDictionary *user = [payload[@"user"] isKindOfClass:NSDictionary.class] ? payload[@"user"] : nil;
                 NSString *resolvedEmail = GYStringValue(user[@"email"]) ?: trimmed;
                 [self_ adoptAccessToken:accessToken
                            refreshToken:refreshToken
                               expiresAt:payload[@"expires_at"]
                                   email:resolvedEmail];
                 GYKeychainStore(resolvedEmail, refreshToken);
                 [self_ setStatus:GYAccountStatusLoggedIn email:resolvedEmail];
                 finish(YES, nil);
               }] resume];
}

- (void)logout {
  [_lock lock];
  _refreshToken = nil;
  _accessToken = nil;
  _accessTokenExpiry = 0;
  [_lock unlock];
  GYKeychainDelete();
  [self setStatus:GYAccountStatusLoggedOut email:@""];
}

// MARK: - Access token

- (void)accessTokenWithCompletion:(void (^)(NSString *_Nullable))completion {
  void (^deliver)(NSString *_Nullable) = ^(NSString *_Nullable token) {
    dispatch_async(dispatch_get_main_queue(), ^{ completion(token); });
  };
  dispatch_async(_queue, ^{
    [self->_lock lock];
    NSString *cached = self->_accessToken;
    const NSTimeInterval expiry = self->_accessTokenExpiry;
    NSString *refreshToken = self->_refreshToken;
    [self->_lock unlock];

    if (refreshToken == nil) {
      deliver(nil);
      return;
    }
    if (cached != nil && expiry - NSDate.date.timeIntervalSince1970 > kExpiryGuard) {
      deliver(cached);
      return;
    }
    [self->_pendingTokenCompletions addObject:deliver];
    if (self->_refreshing) return; // one refresh in flight serves everyone
    self->_refreshing = YES;
    [self refreshWithToken:refreshToken];
  });
}

/// Always called on `_queue` with `_refreshing` already YES.
- (void)refreshWithToken:(NSString *)refreshToken {
  NSMutableURLRequest *request = [self requestForPath:@"/api/auth/me" method:@"GET"];
  [request setValue:[NSString stringWithFormat:@"gsyen_rt=%@", refreshToken] forHTTPHeaderField:@"Cookie"];

  __weak typeof(self) weakSelf = self;
  [[_session dataTaskWithRequest:request
               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                 typeof(self) self_ = weakSelf;
                 if (self_ == nil) return;
                 const NSInteger code = ((NSHTTPURLResponse *)response).statusCode;
                 NSDictionary *payload = error != nil || data == nil
                                             ? nil
                                             : GYSessionPayload([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]);
                 NSString *accessToken = GYStringValue(payload[@"access_token"]);
                 if (accessToken == nil) {
                   NSLog(@"GY account: session refresh failed (HTTP %ld, NSURLError %ld)",
                         (long)code, (long)error.code);
                 }
                 dispatch_async(self_->_queue, ^{
                   if (accessToken != nil) {
                     NSDictionary *user = [payload[@"user"] isKindOfClass:NSDictionary.class] ? payload[@"user"] : nil;
                     NSString *email = GYStringValue(user[@"email"]);
                     // Some backends rotate the refresh token on every use.
                     NSString *rotated = GYStringValue(payload[@"refresh_token"]);
                     [self_ adoptAccessToken:accessToken
                                refreshToken:rotated ?: refreshToken
                                   expiresAt:payload[@"expires_at"]
                                       email:email];
                     if (rotated != nil) GYKeychainStore(email ?: self_.email, rotated);
                     [self_ setStatus:GYAccountStatusLoggedIn email:email];
                   } else if (error == nil && code == 401) {
                     // The session is genuinely dead: forget it. A network
                     // failure, by contrast, keeps the Keychain intact so the
                     // next poll can retry.
                     [self_ logout];
                   }
                   [self_ drainPendingTokenCompletionsWith:accessToken];
                 });
               }] resume];
}

/// Always called on `_queue`.
- (void)drainPendingTokenCompletionsWith:(NSString *_Nullable)token {
  NSArray<void (^)(NSString *_Nullable)> *pending = [_pendingTokenCompletions copy];
  [_pendingTokenCompletions removeAllObjects];
  _refreshing = NO;
  for (void (^completion)(NSString *_Nullable) in pending) completion(token);
}

- (void)adoptAccessToken:(NSString *)accessToken
            refreshToken:(NSString *)refreshToken
               expiresAt:(id)expiresAt
                   email:(NSString *_Nullable)email {
  const NSTimeInterval now = NSDate.date.timeIntervalSince1970;
  NSTimeInterval expiry = 0;
  if ([expiresAt isKindOfClass:NSNumber.class]) expiry = [expiresAt doubleValue];
  if (expiry <= now) expiry = now + 300; // unknown or already-stale: re-check soon
  [_lock lock];
  _accessToken = [accessToken copy];
  _refreshToken = [refreshToken copy];
  _accessTokenExpiry = expiry;
  if (email.length != 0) _email = [email copy];
  [_lock unlock];
}

- (NSMutableURLRequest *)requestForPath:(NSString *)path method:(NSString *)method {
  NSURL *url = [NSURL URLWithString:[kAuthBase stringByAppendingString:path]];
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  request.HTTPMethod = method;
  request.HTTPShouldHandleCookies = NO;
  request.timeoutInterval = kRequestTimeout;
  [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
  return request;
}

@end
