#import "GYClipboardHistory.h"

#import <AppKit/AppKit.h>

static NSUInteger const kGYClipboardMaxEntries = 20;
static NSUInteger const kGYClipboardMaxBytes = 1024 * 1024;  // 1 MiB per entry

@implementation GYClipboardEntry
@end

NSString *GYNewClipboardEntryId(void) {
  return [NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
}

static BOOL GYIsValidEntryId(NSString *entryId) {
  if (![entryId isKindOfClass:NSString.class] || entryId.length < 8 || entryId.length > 128) return NO;
  static NSCharacterSet *disallowed;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    disallowed = [NSCharacterSet characterSetWithCharactersInString:
                      @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"].invertedSet;
  });
  return [entryId rangeOfCharacterFromSet:disallowed].location == NSNotFound;
}

static BOOL GYIsAcceptableText(NSString *text) {
  if (![text isKindOfClass:NSString.class] || text.length == 0) return NO;
  return [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= kGYClipboardMaxBytes;
}

@interface GYClipboardHistory ()
@property(nonatomic, strong) NSMutableArray<GYClipboardEntry *> *items;  // newest first
@property(nonatomic, strong) NSURL *fileURL;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) NSInteger lastChangeCount;
@end

@implementation GYClipboardHistory {
  // GYKeepSync 从自己的串行队列读写历史，捕获则在主线程；两边共用这把锁。
  NSLock *_lock;
}

+ (NSString *)didChangeNotification { return @"GYClipboardHistoryDidChangeNotification"; }

+ (instancetype)sharedHistory {
  static GYClipboardHistory *instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{ instance = [[GYClipboardHistory alloc] initPrivate]; });
  return instance;
}

- (instancetype)init { return [GYClipboardHistory sharedHistory]; }

- (instancetype)initPrivate {
  self = [super init];
  if (!self) return nil;
  _lock = [[NSLock alloc] init];
  NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                        inDomains:NSUserDomainMask].firstObject;
  NSURL *directory = [support URLByAppendingPathComponent:@"GYInput" isDirectory:YES];
  [NSFileManager.defaultManager createDirectoryAtURL:directory
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:nil];
  _fileURL = [directory URLByAppendingPathComponent:@"clipboard-history.tsv"];
  BOOL migrated = NO;
  _items = [[self readAllDidMigrate:&migrated] mutableCopy] ?: [NSMutableArray array];
  _lastChangeCount = NSPasteboard.generalPasteboard.changeCount;
  if (migrated) [self save];  // 旧的两字段行立即改写为四字段
  return self;
}

- (NSArray<GYClipboardEntry *> *)entries {
  [_lock lock];
  NSArray<GYClipboardEntry *> *snapshot = [_items copy];
  [_lock unlock];
  return snapshot;
}

- (void)postDidChange {
  dispatch_block_t post = ^{
    [NSNotificationCenter.defaultCenter postNotificationName:GYClipboardHistory.didChangeNotification object:self];
  };
  if (NSThread.isMainThread) post();
  else dispatch_async(dispatch_get_main_queue(), post);
}

// MARK: Capture

- (void)startCapture {
  if (_timer != nil) return;
  _timer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                            target:self
                                          selector:@selector(pollPasteboard)
                                          userInfo:nil
                                           repeats:YES];
}

- (void)pollPasteboard {
  NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
  if (pasteboard.changeCount == _lastChangeCount) return;
  _lastChangeCount = pasteboard.changeCount;
  // 只收纯文本。复制截图/图片时这里得到 nil，历史不增、Keep 不传，
  // 而且我们没有碰剪贴板，图片仍然可以正常粘贴。
  NSString *text = [pasteboard stringForType:NSPasteboardTypeString];
  if (![text isKindOfClass:NSString.class]) return;
  if (text.length == 0) return;
  // 1 MiB UTF-8 ceiling: oversized copies never enter the stream.
  if ([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > kGYClipboardMaxBytes) return;

  [_lock lock];
  // Consecutive dedupe: identical back-to-back copies collapse into one entry.
  if (_items.count > 0 && [_items.firstObject.text isEqualToString:text]) {
    [_lock unlock];
    return;
  }
  GYClipboardEntry *entry = [[GYClipboardEntry alloc] init];
  entry.text = text;
  entry.unixTime = [NSDate.date timeIntervalSince1970];
  entry.entryId = GYNewClipboardEntryId();
  entry.pendingUpload = YES;
  [_items insertObject:entry atIndex:0];
  while (_items.count > kGYClipboardMaxEntries) [_items removeLastObject];
  [_lock unlock];

  [self save];
  [self postDidChange];
}

- (void)clear {
  [_lock lock];
  [_items removeAllObjects];
  [_lock unlock];
  [self save];
  [self postDidChange];
}

// MARK: Keep 同步入口

- (BOOL)replaceEntries:(NSArray<GYClipboardEntry *> *)entries {
  NSMutableArray<GYClipboardEntry *> *accepted = [NSMutableArray arrayWithCapacity:entries.count];
  NSMutableSet<NSString *> *seenIds = [NSMutableSet set];
  for (GYClipboardEntry *entry in entries) {
    if (![entry isKindOfClass:GYClipboardEntry.class]) continue;
    if (!GYIsValidEntryId(entry.entryId) || !GYIsAcceptableText(entry.text)) continue;
    if ([seenIds containsObject:entry.entryId]) continue;
    if ([accepted.lastObject.text isEqualToString:entry.text]) continue;  // 连续去重
    [seenIds addObject:entry.entryId];
    [accepted addObject:entry];
    if (accepted.count == kGYClipboardMaxEntries) break;
  }
  [_lock lock];
  _items = accepted;
  [_lock unlock];
  [self save];
  [self postDidChange];
  return YES;
}

- (BOOL)publishRemoteTextToSystemPasteboard:(NSString *)text {
  if (!GYIsAcceptableText(text)) return NO;
  dispatch_block_t write = ^{
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];
    // 吞掉自己造成的变化：否则下一次轮询会把它当成用户复制再传回 Keep，形成回环。
    self.lastChangeCount = pasteboard.changeCount;
  };
  if (NSThread.isMainThread) write();
  else dispatch_sync(dispatch_get_main_queue(), write);
  return YES;
}

// MARK: Persistence (Windows-compatible tsv)

static NSString *GYEscape(NSString *text) {
  NSMutableString *out = [NSMutableString stringWithCapacity:text.length];
  for (NSUInteger i = 0; i < text.length; ++i) {
    unichar ch = [text characterAtIndex:i];
    if (ch == '\\') [out appendString:@"\\\\"];
    else if (ch == '\t') [out appendString:@"\\t"];
    else if (ch == '\r') [out appendString:@"\\r"];
    else if (ch == '\n') [out appendString:@"\\n"];
    else [out appendFormat:@"%C", ch];
  }
  return out;
}

static NSString *GYUnescape(NSString *escaped) {
  NSMutableString *out = [NSMutableString stringWithCapacity:escaped.length];
  BOOL pending = NO;
  for (NSUInteger i = 0; i < escaped.length; ++i) {
    unichar ch = [escaped characterAtIndex:i];
    if (!pending) {
      if (ch == '\\') pending = YES;
      else [out appendFormat:@"%C", ch];
      continue;
    }
    if (ch == 't') [out appendString:@"\t"];
    else if (ch == 'r') [out appendString:@"\r"];
    else if (ch == 'n') [out appendString:@"\n"];
    else [out appendFormat:@"%C", ch];
    pending = NO;
  }
  return out;
}

- (NSArray<GYClipboardEntry *> *)readAllDidMigrate:(BOOL *)didMigrate {
  NSString *content = [NSString stringWithContentsOfURL:_fileURL
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
  if (![content isKindOfClass:NSString.class]) return @[];
  NSMutableArray<GYClipboardEntry *> *oldest = [NSMutableArray array];
  for (NSString *line in [content componentsSeparatedByString:@"\n"]) {
    if (line.length == 0) continue;
    // 转义后的正文里不会出现真实制表符，所以按前三个制表符切分是安全的。
    NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\t"];
    GYClipboardEntry *entry = [[GYClipboardEntry alloc] init];
    if (fields.count >= 4) {
      entry.entryId = fields[0];
      entry.unixTime = fields[1].doubleValue;
      entry.pendingUpload = [fields[2] isEqualToString:@"1"];
      entry.text = GYUnescape([[fields subarrayWithRange:NSMakeRange(3, fields.count - 3)]
                                  componentsJoinedByString:@"\t"]);
    } else if (fields.count == 2) {
      // 旧的两字段行：补 ID，标为待上传，让下一轮同步把它补进 Keep。
      // 这个写入端本来就做反斜杠转义，所以这里照常反转义。
      entry.entryId = GYNewClipboardEntryId();
      entry.unixTime = fields[0].doubleValue;
      entry.pendingUpload = YES;
      entry.text = GYUnescape(fields[1]);
      if (didMigrate != NULL) *didMigrate = YES;
    } else {
      continue;
    }
    if (!GYIsValidEntryId(entry.entryId)) {
      entry.entryId = GYNewClipboardEntryId();
      if (didMigrate != NULL) *didMigrate = YES;
    }
    if (!GYIsAcceptableText(entry.text)) continue;
    [oldest addObject:entry];
  }
  // 文件最旧在前；内存最新在前。
  return [[oldest reverseObjectEnumerator] allObjects];
}

- (void)save {
  [_lock lock];
  NSArray<GYClipboardEntry *> *snapshot = [_items copy];
  [_lock unlock];
  NSMutableString *out = [NSMutableString string];
  for (GYClipboardEntry *entry in [[snapshot reverseObjectEnumerator] allObjects]) {
    [out appendFormat:@"%@\t%.0f\t%@\t%@\n", entry.entryId, entry.unixTime,
                      entry.pendingUpload ? @"1" : @"0", GYEscape(entry.text)];
  }
  [out writeToURL:_fileURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

@end
