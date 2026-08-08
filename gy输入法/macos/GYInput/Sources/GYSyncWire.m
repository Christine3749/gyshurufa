#import "GYSyncWire.h"

#import <CommonCrypto/CommonDigest.h>
#import <errno.h>
#import <string.h>

static NSUInteger const kGYMaxWireChangesPerPayload = 64;
// 2000-01-01T00:00:00Z in ms — anything before this is treated as a
// malformed payload, same sanity bound as the Windows client.
static unsigned long long const kGYMinValidCapturedAtMs = 946684800000ULL;

@implementation GYWireChange
- (instancetype)init {
  self = [super init];
  if (self) _originDeviceId = @"";
  return self;
}
@end

BOOL GYIsValidEntryId(NSString *entryId) {
  if (![entryId isKindOfClass:NSString.class] || entryId.length < 8 || entryId.length > 128) return NO;
  static NSCharacterSet *disallowed;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    disallowed = [NSCharacterSet characterSetWithCharactersInString:
                      @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"].invertedSet;
  });
  return [entryId rangeOfCharacterFromSet:disallowed].location == NSNotFound;
}

/// A wire-v4 originDeviceId field is either empty (no known origin) or a
/// device id in the same [A-Za-z0-9_-]{8,128} shape as an entry id (spec
/// §7.1: device ids and entry ids share one id grammar in this protocol).
static BOOL GYIsValidOriginDeviceIdField(NSString *value) {
  return value.length == 0 || GYIsValidEntryId(value);
}

/// Strict ASCII '0'-'9' only — deliberately NOT
/// NSCharacterSet.decimalDigitCharacterSet, which matches any Unicode
/// decimal digit (Arabic-Indic, full-width, etc). A sequence/cursor/size/
/// capturedAt field that passed a Unicode-digit check but contained one of
/// those would then silently truncate under strtoull, which only
/// understands ASCII — see GYParseAllASCIIDigitsUInt64 below.
static BOOL GYIsAllASCIIDigits(NSString *value, NSUInteger minLength, NSUInteger maxLength) {
  if (![value isKindOfClass:NSString.class] || value.length < minLength || value.length > maxLength) return NO;
  for (NSUInteger i = 0; i < value.length; ++i) {
    unichar ch = [value characterAtIndex:i];
    if (ch < '0' || ch > '9') return NO;
  }
  return YES;
}

/// No leading zero unless the value is exactly "0" — required so that
/// ORDER BY LENGTH(sequence), sequence in GYBlockStore correctly emulates
/// numeric ordering for arbitrary-precision non-negative integers (a
/// leading zero would make two strings of unequal true magnitude compare as
/// equal length, e.g. "007" vs "100").
static BOOL GYHasNoLeadingZero(NSString *value) {
  return value.length <= 1 || [value characterAtIndex:0] != '0';
}

BOOL GYIsDecimalSequence(NSString *value) {
  // Keep never assigns sequence 0, and GYBlockStore's sort invariant depends
  // on no leading zeros (see GYHasNoLeadingZero).
  return GYIsAllASCIIDigits(value, 1, 20) && ![value isEqualToString:@"0"] && GYHasNoLeadingZero(value);
}

BOOL GYIsDecimalCursor(NSString *value) {
  // "0" is the one valid cursor value that is also its own leading zero —
  // GYHasNoLeadingZero already special-cases length <= 1.
  return GYIsAllASCIIDigits(value, 1, 20) && GYHasNoLeadingZero(value);
}

/// Parses a field that must be entirely ASCII decimal digits (no sign, no
/// whitespace, no trailing garbage) into an unsigned 64-bit integer.
/// Deliberately does not just call strtoull(field, NULL, 10) directly: with
/// a NULL endptr, strtoull silently stops at the first non-digit character
/// and returns whatever numeric prefix it found — "123abc" would parse as
/// 123 instead of being rejected, and a malformed capturedAtMs/size field
/// would corrupt data instead of failing the whole payload closed.
static BOOL GYParseAllASCIIDigitsUInt64(NSString *field, unsigned long long *out) {
  if (!GYIsAllASCIIDigits(field, 1, 20)) return NO;
  char *endptr = NULL;
  const char *cstr = field.UTF8String;
  errno = 0;
  unsigned long long value = strtoull(cstr, &endptr, 10);
  if (endptr != cstr + strlen(cstr) || errno == ERANGE) return NO;
  *out = value;
  return YES;
}

BOOL GYIsHexSHA256(NSString *value) {
  if (![value isKindOfClass:NSString.class] || value.length != 64) return NO;
  static NSCharacterSet *hex;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"].invertedSet; });
  return [value rangeOfCharacterFromSet:hex].location == NSNotFound;
}

NSString *GYSHA256Hex(NSData *data) {
  unsigned char digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
  static const char *kHex = "0123456789abcdef";
  char hex[CC_SHA256_DIGEST_LENGTH * 2 + 1];
  hex[CC_SHA256_DIGEST_LENGTH * 2] = '\0';
  for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; ++i) {
    hex[i * 2] = kHex[(digest[i] >> 4) & 0xF];
    hex[i * 2 + 1] = kHex[digest[i] & 0xF];
  }
  return [NSString stringWithUTF8String:hex];
}

/// Shared by the v3 and v4 parsers — the only difference between the two
/// wire shapes is one trailing originDeviceId field on every line (see the
/// NAMING note in GYSyncWire.h), so `withOrigin` just shifts the expected
/// field counts by one and, when true, reads and validates that last field.
static NSArray<GYWireChange *> *_Nullable GYParseSyncWirePayloadShape(NSString *_Nullable base64Payload,
                                                                       BOOL withOrigin) {
  if (base64Payload.length == 0) return @[];
  NSData *decoded = [[NSData alloc] initWithBase64EncodedString:base64Payload options:0];
  if (decoded == nil) return nil;
  NSString *body = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
  if (body == nil) return nil;
  const NSInteger originShift = withOrigin ? 1 : 0;
  NSMutableArray<GYWireChange *> *changes = [NSMutableArray array];
  for (NSString *line in [body componentsSeparatedByString:@"\n"]) {
    if (line.length == 0) continue;
    NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\t"];
    NSString *type = fields.firstObject;
    if (!([type isEqualToString:@"T"] || [type isEqualToString:@"I"] || [type isEqualToString:@"D"])) return nil;
    const BOOL deleted = [type isEqualToString:@"D"];
    const BOOL image = [type isEqualToString:@"I"];
    const NSInteger expected = (deleted ? 3 : (image ? 7 : 5)) + originShift;
    if ((NSInteger)fields.count != expected) return nil;
    if (!GYIsDecimalSequence(fields[1])) return nil;
    NSString *entryId = fields[2];
    if (!GYIsValidEntryId(entryId)) return nil;
    NSString *origin = @"";
    if (withOrigin) {
      origin = fields.lastObject;
      if (!GYIsValidOriginDeviceIdField(origin)) return nil;
    }

    if (deleted) {
      GYWireChange *change = [[GYWireChange alloc] init];
      change.kind = GYWireChangeDelete;
      change.entryId = entryId;
      change.originDeviceId = origin;
      [changes addObject:change];
      if (changes.count > kGYMaxWireChangesPerPayload) return nil;
      continue;
    }

    unsigned long long capturedAtMs = 0;
    if (!GYParseAllASCIIDigitsUInt64(fields[3], &capturedAtMs)) return nil;
    if (capturedAtMs < kGYMinValidCapturedAtMs) return nil;
    GYBlock *block = [[GYBlock alloc] init];
    block.entryId = entryId;
    block.capturedAt = (NSTimeInterval)capturedAtMs / 1000.0;
    block.state = GYBlockStateConfirmed;
    block.sequence = fields[1];
    block.originDeviceId = origin.length > 0 ? origin : nil;

    if (image) {
      if (![fields[4] isEqualToString:@"image/png"]) return nil;
      unsigned long long size = 0;
      if (!GYParseAllASCIIDigitsUInt64(fields[5], &size)) return nil;
      if (size == 0 || size > 10 * 1024 * 1024) return nil;
      if (!GYIsHexSHA256(fields[6])) return nil;
      block.kind = GYBlockKindImage;
      block.byteSize = (NSUInteger)size;
      block.sha256 = fields[6];
    } else {
      NSData *textData = [[NSData alloc] initWithBase64EncodedString:fields[4] options:0];
      NSString *text = textData == nil ? nil : [[NSString alloc] initWithData:textData encoding:NSUTF8StringEncoding];
      if (text.length == 0) return nil;
      block.kind = GYBlockKindText;
      block.text = text;
    }
    GYWireChange *change = [[GYWireChange alloc] init];
    change.kind = GYWireChangeAdd;
    change.block = block;
    change.originDeviceId = origin;
    [changes addObject:change];
    if (changes.count > kGYMaxWireChangesPerPayload) return nil;
  }
  return changes;
}

NSArray<GYWireChange *> *_Nullable GYParseSyncWireV3Payload(NSString *_Nullable base64Payload) {
  return GYParseSyncWirePayloadShape(base64Payload, NO);
}

NSArray<GYWireChange *> *_Nullable GYParseSyncWireV4Payload(NSString *_Nullable base64Payload) {
  return GYParseSyncWirePayloadShape(base64Payload, YES);
}

NSString *_Nullable GYParseAckSequence(NSData *_Nullable data) {
  if (data == nil) return nil;
  id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  NSDictionary *envelope = [json isKindOfClass:NSDictionary.class] ? json : nil;
  NSDictionary *payload = [envelope[@"data"] isKindOfClass:NSDictionary.class] ? envelope[@"data"] : nil;
  NSDictionary *ack = [payload[@"ack"] isKindOfClass:NSDictionary.class] ? payload[@"ack"] : nil;
  id sequence = ack[@"sequence"];
  if (![sequence isKindOfClass:NSString.class] || !GYIsDecimalSequence(sequence)) return nil;
  return sequence;
}

NSArray<GYWireChange *> *_Nullable GYParseSyncPage(NSData *_Nullable data,
                                                     NSString *_Nullable *outCursor,
                                                     NSNumber *_Nullable *outHasMore) {
  if (data == nil) return nil;
  id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  NSDictionary *envelope = [json isKindOfClass:NSDictionary.class] ? json : nil;
  NSDictionary *payload = [envelope[@"data"] isKindOfClass:NSDictionary.class] ? envelope[@"data"] : nil;
  id cursor = payload[@"cursor"];
  id hasMore = payload[@"hasMore"];
  id wirePayload = payload[@"payload"];
  if (![cursor isKindOfClass:NSString.class] || !GYIsDecimalCursor(cursor)) return nil;
  if (![hasMore isKindOfClass:NSNumber.class]) return nil;
  NSArray<GYWireChange *> *changes = GYParseSyncWireV3Payload([wirePayload isKindOfClass:NSString.class] ? wirePayload : nil);
  if (changes == nil) return nil;
  if (outCursor != NULL) *outCursor = cursor;
  if (outHasMore != NULL) *outHasMore = hasMore;
  return changes;
}
