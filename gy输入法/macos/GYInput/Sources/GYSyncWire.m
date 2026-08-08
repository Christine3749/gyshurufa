#import "GYSyncWire.h"

static NSUInteger const kGYMaxWireChangesPerPayload = 64;
// 2000-01-01T00:00:00Z in ms — anything before this is treated as a
// malformed payload, same sanity bound as the Windows client.
static unsigned long long const kGYMinValidCapturedAtMs = 946684800000ULL;

@implementation GYWireChange
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

BOOL GYIsDecimalSequence(NSString *value) {
  if (![value isKindOfClass:NSString.class] || value.length == 0 || value.length > 20) return NO;
  if ([value isEqualToString:@"0"]) return NO;
  static NSCharacterSet *nonDigits;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet; });
  return [value rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

BOOL GYIsDecimalCursor(NSString *value) {
  if (![value isKindOfClass:NSString.class] || value.length == 0 || value.length > 20) return NO;
  static NSCharacterSet *nonDigits;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet; });
  return [value rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

BOOL GYIsHexSHA256(NSString *value) {
  if (![value isKindOfClass:NSString.class] || value.length != 64) return NO;
  static NSCharacterSet *hex;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"].invertedSet; });
  return [value rangeOfCharacterFromSet:hex].location == NSNotFound;
}

NSArray<GYWireChange *> *_Nullable GYParseSyncWirePayload(NSString *_Nullable base64Payload) {
  if (base64Payload.length == 0) return @[];
  NSData *decoded = [[NSData alloc] initWithBase64EncodedString:base64Payload options:0];
  if (decoded == nil) return nil;
  NSString *body = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
  if (body == nil) return nil;
  NSMutableArray<GYWireChange *> *changes = [NSMutableArray array];
  for (NSString *line in [body componentsSeparatedByString:@"\n"]) {
    if (line.length == 0) continue;
    NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\t"];
    NSString *type = fields.firstObject;
    if (!([type isEqualToString:@"T"] || [type isEqualToString:@"I"] || [type isEqualToString:@"D"])) return nil;
    const BOOL deleted = [type isEqualToString:@"D"];
    const BOOL image = [type isEqualToString:@"I"];
    if (deleted && fields.count != 3) return nil;
    if (!deleted && ((!image && fields.count != 5) || (image && fields.count != 7))) return nil;
    if (!GYIsDecimalSequence(fields[1])) return nil;
    NSString *entryId = fields[2];
    if (!GYIsValidEntryId(entryId)) return nil;

    if (deleted) {
      GYWireChange *change = [[GYWireChange alloc] init];
      change.kind = GYWireChangeDelete;
      change.entryId = entryId;
      [changes addObject:change];
      if (changes.count > kGYMaxWireChangesPerPayload) return nil;
      continue;
    }

    unsigned long long capturedAtMs = strtoull(fields[3].UTF8String, NULL, 10);
    if (capturedAtMs < kGYMinValidCapturedAtMs) return nil;
    GYBlock *block = [[GYBlock alloc] init];
    block.entryId = entryId;
    block.capturedAt = (NSTimeInterval)capturedAtMs / 1000.0;
    block.state = GYBlockStateConfirmed;
    block.sequence = fields[1];

    if (image) {
      if (![fields[4] isEqualToString:@"image/png"]) return nil;
      unsigned long long size = strtoull(fields[5].UTF8String, NULL, 10);
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
    [changes addObject:change];
    if (changes.count > kGYMaxWireChangesPerPayload) return nil;
  }
  return changes;
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
  NSArray<GYWireChange *> *changes = GYParseSyncWirePayload([wirePayload isKindOfClass:NSString.class] ? wirePayload : nil);
  if (changes == nil) return nil;
  if (outCursor != NULL) *outCursor = cursor;
  if (outHasMore != NULL) *outHasMore = hasMore;
  return changes;
}
