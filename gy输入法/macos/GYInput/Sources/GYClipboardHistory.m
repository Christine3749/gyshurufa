#import "GYClipboardHistory.h"

#import <AppKit/AppKit.h>

static NSUInteger const kGYClipboardMaxEntries = 20;
static NSUInteger const kGYClipboardMaxBytes = 1024 * 1024;  // 1 MiB per entry
// macOS 没有剪贴板变化通知，只能轮询 changeCount。0.15s 让"复制→出现在列表"
// 接近瞬时，同时把"两次复制挨得太近、只发现一次"的窗口压到最窄。
// changeCount 是一次很轻的读取，这个频率的开销可以忽略。
static NSTimeInterval const kGYPasteboardPollInterval = 0.15;
// 延迟供给的剪贴板最多等这么多轮（约 1.2 秒）。有上限才不会为纯图片、
// 纯文件的复制无限重试下去。
static NSInteger const kGYPasteboardMaxDeferredPolls = 8;

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
  // 正在等待数据到位的那次 changeCount，以及已经等了几轮。
  NSInteger _deferredChangeCount;
  NSInteger _deferredPolls;
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
  _deferredChangeCount = NSNotFound;
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
  _timer = [NSTimer scheduledTimerWithTimeInterval:kGYPasteboardPollInterval
                                            target:self
                                          selector:@selector(pollPasteboard)
                                          userInfo:nil
                                           repeats:YES];
}

/// 记账：这次 changeCount 已经处理完，不再回头看它。
- (void)commitChangeCount:(NSInteger)changeCount {
  _lastChangeCount = changeCount;
  _deferredChangeCount = NSNotFound;
  _deferredPolls = 0;
}

- (void)pollPasteboard {
  NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
  const NSInteger changeCount = pasteboard.changeCount;
  if (changeCount == _lastChangeCount) return;
  if (changeCount != _deferredChangeCount) {  // 新的一次变化，重新计等待轮数
    _deferredChangeCount = changeCount;
    _deferredPolls = 0;
  }

  // 只收纯文本。复制截图/图片时这里得到 nil，历史不增、Keep 不传，
  // 而且我们没有碰剪贴板，图片仍然可以正常粘贴。
  NSString *text = [pasteboard stringForType:NSPasteboardTypeString];
  if (![text isKindOfClass:NSString.class] || text.length == 0) {
    // 关键：拿不到文本时**不能**直接记账。很多程序（浏览器、Office、
    // Electron 系）是先 clearContents 把 changeCount 顶上去，之后才把数据
    // 填进来；轮询撞在这个空窗里就会读到 nil。以前这里已经推进了
    // _lastChangeCount，于是那一次复制永久丢失——用户表现为"复制没反应，
    // 得再复制一次"。
    //
    // 区分两种 nil：
    //   声明了文本类型（或还没声明任何类型）→ 数据没到位，下一轮再看；
    //   声明了别的类型但没有文本         → 图片/文件，本来就没东西可抓。
    const BOOL declaresText = [pasteboard availableTypeFromArray:@[NSPasteboardTypeString]] != nil;
    const BOOL declaresNothingYet = pasteboard.types.count == 0;
    if ((declaresText || declaresNothingYet) && ++_deferredPolls < kGYPasteboardMaxDeferredPolls) {
      return;  // 不记账：下一轮还会回到这次 changeCount
    }
    [self commitChangeCount:changeCount];
    return;
  }
  // 读到内容之后才记账。
  [self commitChangeCount:changeCount];
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
  // 稳态必须是"什么都不做"。否则：每轮同步都无条件发变更通知，
  // GYKeepSync 收到就 wake，立刻又跑一轮 —— _syncing 只挡并发、
  // 挡不住首尾相接，于是变成连续不断的网络请求加每轮一次写盘，
  // 设置面板开着还会跟着每轮重建列表。这就是"很卡"的来源。
  BOOL identical = accepted.count == _items.count;
  for (NSUInteger i = 0; identical && i < accepted.count; ++i) {
    GYClipboardEntry *incoming = accepted[i];
    GYClipboardEntry *current = _items[i];
    if (![incoming.entryId isEqualToString:current.entryId] ||
        incoming.pendingUpload != current.pendingUpload) {
      identical = NO;
    }
  }
  if (identical) {
    [_lock unlock];
    return YES;
  }
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
    // 同时清掉延迟等待状态，避免把这次写入误当成"还在等数据"的那一次。
    [self commitChangeCount:pasteboard.changeCount];
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
