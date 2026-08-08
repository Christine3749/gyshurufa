#import "GYClipboardHistory.h"
#import "GYSelfWriteFingerprint.h"
#import "GYSyncWire.h"

#import <AppKit/AppKit.h>

// macOS 没有剪贴板变化通知，只能轮询 changeCount。
// 最坏发现延迟 ≈ 200ms，平均 ≈ 100ms，常驻进程开销可忽略。
//
// 必须如实说明：系统不提供剪贴板历史队列，所以**任何**轮询间隔都无法在数学上
// 保证捕获间隔内发生的两次极速复制——第二次会覆盖第一次，第一次无从得知。
// 缩短间隔只能把概率压小。而"延迟供给导致的永久丢失"是另一回事，那个由下面
// 的记账顺序修复为零。
static NSTimeInterval const kGYPasteboardPollInterval = 0.2;
// 延迟供给的剪贴板最多等这么多轮（约 1.2 秒）。有上限才不会为纯图片、
// 纯文件的复制无限重试下去。
static NSInteger const kGYPasteboardMaxDeferredPolls = 8;
static NSUInteger const kGYHeadLimit = 20;
static NSUInteger const kGYMaxImageBytes = 10 * 1024 * 1024;  // spec §7.3

NSString *GYNewClipboardEntryId(void) {
  return [NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
}

@implementation GYClipboardEntry
+ (instancetype)fromBlock:(GYBlock *)block {
  GYClipboardEntry *entry = [[GYClipboardEntry alloc] init];
  entry.entryId = block.entryId;
  entry.kind = block.kind;
  entry.text = block.text ?: @"";
  entry.sha256 = block.sha256;
  entry.byteSize = block.byteSize;
  entry.blobPath = block.blobPath;
  entry.unixTime = block.capturedAt;
  entry.pendingUpload = (block.state == GYBlockStateQueued);
  return entry;
}
@end

@interface GYClipboardHistory ()
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) NSInteger lastChangeCount;
@end

@implementation GYClipboardHistory {
  // 正在等待数据到位的那次 changeCount，以及已经等了几轮。
  NSInteger _deferredChangeCount;
  NSInteger _deferredPolls;
  // 本程序刚写入剪贴板的文本内容指纹，用于识别"这次变化是我自己造成的"。
  // 只按内容匹配、不按"跳过下一个 changeCount"，否则用户在我们写入的同一
  // 瞬间按下 ⌘C，那次复制会被当成自己的写入吞掉。
  NSString *_selfWrittenText;
  NSInteger _selfWrittenChangeCount;
  // 同上，但用于图片：内容指纹换成 SHA-256。
  NSString *_selfWrittenImageSHA256;
  NSInteger _selfWrittenImageChangeCount;
  NSURL *_blobDirectory;
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
  NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                        inDomains:NSUserDomainMask].firstObject;
  _blobDirectory = [[support URLByAppendingPathComponent:@"GYInput" isDirectory:YES]
      URLByAppendingPathComponent:@"blobs" isDirectory:YES];
  [NSFileManager.defaultManager createDirectoryAtURL:_blobDirectory
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:nil];
  [GYBlockStore.sharedStore migrateLegacyTSVIfNeeded];
  _lastChangeCount = NSPasteboard.generalPasteboard.changeCount;
  _deferredChangeCount = NSNotFound;
  _selfWrittenChangeCount = NSNotFound;
  _selfWrittenImageChangeCount = NSNotFound;
  return self;
}

- (NSArray<GYClipboardEntry *> *)entries {
  NSArray<GYBlock *> *blocks = [GYBlockStore.sharedStore headProjectionWithLimit:kGYHeadLimit];
  NSMutableArray<GYClipboardEntry *> *entries = [NSMutableArray arrayWithCapacity:blocks.count];
  for (GYBlock *block in blocks) [entries addObject:[GYClipboardEntry fromBlock:block]];
  return entries;
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
  // changeCount 只增不减，所以一旦越过我们写入的那一次，指纹再也不可能命中，
  // 及时释放（内容最大可达 1 MiB / 10 MiB）。
  if (_selfWrittenChangeCount != NSNotFound && changeCount > _selfWrittenChangeCount) {
    _selfWrittenText = nil;
    _selfWrittenChangeCount = NSNotFound;
  }
  if (_selfWrittenImageChangeCount != NSNotFound && changeCount > _selfWrittenImageChangeCount) {
    _selfWrittenImageSHA256 = nil;
    _selfWrittenImageChangeCount = NSNotFound;
  }

  NSString *text = [pasteboard stringForType:NSPasteboardTypeString];

  // 是不是我们自己刚写进去的远端文本？必须内容和 changeCount 同时对上才算。
  if (GYIsOwnPasteboardWrite(_selfWrittenText, _selfWrittenChangeCount, text, changeCount)) {
    _selfWrittenText = nil;
    _selfWrittenChangeCount = NSNotFound;
    [self commitChangeCount:changeCount];  // 记账但不入库，避免回传成环
    return;
  }

  if (![text isKindOfClass:NSString.class] || text.length == 0) {
    // 关键：拿不到文本时**不能**直接记账。很多程序（浏览器、Office、
    // Electron 系）是先 clearContents 把 changeCount 顶上去，之后才把数据
    // 填进来；轮询撞在这个空窗里就会读到 nil。
    const BOOL declaresText = [pasteboard availableTypeFromArray:@[NSPasteboardTypeString]] != nil;
    const BOOL declaresNothingYet = pasteboard.types.count == 0;
    if ((declaresText || declaresNothingYet) && ++_deferredPolls < kGYPasteboardMaxDeferredPolls) {
      return;  // 不记账：下一轮还会回到这次 changeCount
    }
    [self handleNonTextPasteboard:pasteboard changeCount:changeCount];
    return;
  }
  // 读到内容之后才记账。
  [self commitChangeCount:changeCount];
  // 连续去重：与 HEAD 最新一条完全相同则忽略（例如某些程序在同一次操作里
  // 把同一段文字连续两次写入剪贴板）。
  GYClipboardEntry *currentHead = self.entries.firstObject;
  if (currentHead != nil && currentHead.kind == GYBlockKindText && [currentHead.text isEqualToString:text]) return;
  GYBlock *block = [GYBlockStore.sharedStore insertCapturedTextBlock:text
                                                            capturedAt:NSDate.date.timeIntervalSince1970
                                                              entryId:GYNewClipboardEntryId()];
  if (block == nil) return;  // oversized (>1 MiB) or empty: silently dropped, same as before
  [self postDidChange];
}

/// 明确判定为"当前版本不同步的类型"后的处理。记账在这里发生，所以这一次
/// changeCount 不会被反复重试拖住后面的复制。
- (void)handleNonTextPasteboard:(NSPasteboard *)pasteboard changeCount:(NSInteger)changeCount {
  [self commitChangeCount:changeCount];
  NSData *pngData = [self pngDataFromPasteboard:pasteboard];
  if (pngData != nil) {
    [self captureImageData:pngData changeCount:changeCount];
    return;
  }
  if ([pasteboard availableTypeFromArray:@[NSPasteboardTypeFileURL]] != nil) {
    return;  // TODO(file-sync): 文件块，先同步元数据卡片（spec §8.4，超出本轮范围）
  }
  // 其余（RTF 专有格式、自定义 UTI 等）：本版不处理，但已明确记账。
}

/// PNG 优先，TIFF 后台转 PNG（spec §7.3/§8.3）。
- (nullable NSData *)pngDataFromPasteboard:(NSPasteboard *)pasteboard {
  NSData *png = [pasteboard dataForType:NSPasteboardTypePNG];
  if (png.length > 0) return png;
  NSData *tiff = [pasteboard dataForType:NSPasteboardTypeTIFF];
  if (tiff.length == 0) return nil;
  NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:tiff];
  if (rep == nil) return nil;
  return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

- (void)captureImageData:(NSData *)pngData changeCount:(NSInteger)changeCount {
  if (pngData.length == 0 || pngData.length > kGYMaxImageBytes) return;  // 超限仅本机提示交给设置页
  NSString *sha256 = GYSHA256Hex(pngData);

  // 是不是我们自己刚写进去的远端图片？
  if (GYIsOwnPasteboardWrite(_selfWrittenImageSHA256, _selfWrittenImageChangeCount, sha256, changeCount)) {
    _selfWrittenImageSHA256 = nil;
    _selfWrittenImageChangeCount = NSNotFound;
    return;
  }

  // 连续去重：同一张图片背靠背再次出现（部分程序在一次操作里写两次剪贴板）。
  GYClipboardEntry *currentHead = self.entries.firstObject;
  if (currentHead != nil && currentHead.kind == GYBlockKindImage && [currentHead.sha256 isEqualToString:sha256]) return;

  NSString *entryId = GYNewClipboardEntryId();
  NSURL *blobURL = [_blobDirectory URLByAppendingPathComponent:[entryId stringByAppendingPathExtension:@"png"]];
  if (![pngData writeToURL:blobURL atomically:YES]) return;
  GYBlock *block = [GYBlockStore.sharedStore insertCapturedImageBlockAt:NSDate.date.timeIntervalSince1970
                                                                 entryId:entryId
                                                                  sha256:sha256
                                                                byteSize:pngData.length
                                                                blobPath:blobURL.path];
  if (block == nil) return;
  [self postDidChange];
}

- (void)clear {
  [GYBlockStore.sharedStore clearAllBlocks];
  [self postDidChange];
}

// MARK: Publish to system pasteboard

- (BOOL)publishRemoteTextToSystemPasteboard:(NSString *)text {
  if (![text isKindOfClass:NSString.class] || text.length == 0) return NO;
  dispatch_block_t write = ^{
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];
    // 记下"我刚写了什么"，而不是直接把 _lastChangeCount 推到当前值——见
    // pollPasteboard 顶部注释：直接记账会吞掉用户插进来的那次真实复制。
    self->_selfWrittenText = [text copy];
    self->_selfWrittenChangeCount = pasteboard.changeCount;
  };
  if (NSThread.isMainThread) write();
  else dispatch_sync(dispatch_get_main_queue(), write);
  return YES;
}

- (BOOL)publishRemoteImageToSystemPasteboard:(NSData *)pngData {
  if (pngData.length == 0) return NO;
  NSString *sha256 = GYSHA256Hex(pngData);
  dispatch_block_t write = ^{
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setData:pngData forType:NSPasteboardTypePNG];
    self->_selfWrittenImageSHA256 = sha256;
    self->_selfWrittenImageChangeCount = pasteboard.changeCount;
  };
  if (NSThread.isMainThread) write();
  else dispatch_sync(dispatch_get_main_queue(), write);
  return YES;
}

- (BOOL)republishEntryToSystemPasteboard:(GYClipboardEntry *)entry {
  if (entry.kind == GYBlockKindImage) {
    NSData *data = [self imageDataForEntry:entry];
    if (data == nil) return NO;
    return [self publishRemoteImageToSystemPasteboard:data];
  }
  return [self publishRemoteTextToSystemPasteboard:entry.text];
}

- (nullable NSData *)imageDataForEntry:(GYClipboardEntry *)entry {
  if (entry.blobPath.length == 0) return nil;
  return [NSData dataWithContentsOfFile:entry.blobPath];
}

@end
