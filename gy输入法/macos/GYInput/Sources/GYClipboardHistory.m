#import "GYClipboardHistory.h"

#import <AppKit/AppKit.h>

static NSUInteger const kGYClipboardMaxEntries = 20;
static NSUInteger const kGYClipboardMaxBytes = 1024 * 1024;  // 1 MiB per entry

@implementation GYClipboardEntry
@end

@interface GYClipboardHistory ()
@property(nonatomic, strong) NSMutableArray<GYClipboardEntry *> *items;  // newest first
@property(nonatomic, strong) NSURL *fileURL;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) NSInteger lastChangeCount;
@end

@implementation GYClipboardHistory

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
  NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                        inDomains:NSUserDomainMask].firstObject;
  NSURL *directory = [support URLByAppendingPathComponent:@"GYInput" isDirectory:YES];
  [NSFileManager.defaultManager createDirectoryAtURL:directory
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:nil];
  _fileURL = [directory URLByAppendingPathComponent:@"clipboard-history.tsv"];
  _items = [[self readAll] mutableCopy] ?: [NSMutableArray array];
  _lastChangeCount = NSPasteboard.generalPasteboard.changeCount;
  return self;
}

- (NSArray<GYClipboardEntry *> *)entries { return [_items copy]; }

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
  NSString *text = [pasteboard stringForType:NSPasteboardTypeString];
  if (![text isKindOfClass:NSString.class]) return;
  if (text.length == 0) return;
  // 1 MiB UTF-8 ceiling: oversized copies never enter the stream.
  if ([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > kGYClipboardMaxBytes) return;
  // Consecutive dedupe: identical back-to-back copies collapse into one entry.
  if (_items.count > 0 && [_items.firstObject.text isEqualToString:text]) return;

  GYClipboardEntry *entry = [[GYClipboardEntry alloc] init];
  entry.text = text;
  entry.unixTime = [NSDate.date timeIntervalSince1970];
  [_items insertObject:entry atIndex:0];
  while (_items.count > kGYClipboardMaxEntries) [_items removeLastObject];
  [self save];
  [NSNotificationCenter.defaultCenter postNotificationName:GYClipboardHistory.didChangeNotification object:self];
}

- (void)clear {
  [_items removeAllObjects];
  [self save];
  [NSNotificationCenter.defaultCenter postNotificationName:GYClipboardHistory.didChangeNotification object:self];
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

- (NSArray<GYClipboardEntry *> *)readAll {
  NSString *content = [NSString stringWithContentsOfURL:_fileURL
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
  if (![content isKindOfClass:NSString.class]) return @[];
  NSMutableArray<GYClipboardEntry *> *oldest = [NSMutableArray array];
  for (NSString *line in [content componentsSeparatedByString:@"\n"]) {
    if (line.length == 0) continue;
    NSRange tab = [line rangeOfString:@"\t"];
    if (tab.location == NSNotFound) continue;
    GYClipboardEntry *entry = [[GYClipboardEntry alloc] init];
    entry.unixTime = [[line substringToIndex:tab.location] doubleValue];
    entry.text = GYUnescape([line substringFromIndex:tab.location + 1]);
    [oldest addObject:entry];
  }
  // 文件最旧在前；内存最新在前。
  return [[oldest reverseObjectEnumerator] allObjects];
}

- (void)save {
  NSMutableString *out = [NSMutableString string];
  for (GYClipboardEntry *entry in [[_items reverseObjectEnumerator] allObjects]) {
    [out appendFormat:@"%.0f\t%@\n", entry.unixTime, GYEscape(entry.text)];
  }
  [out writeToURL:_fileURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

@end
