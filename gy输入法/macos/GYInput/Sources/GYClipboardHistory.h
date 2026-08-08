// GYClipboardHistory — captures the system pasteboard (text + PNG images)
// and exposes the HEAD-20 "recent GY info stream" view (spec §3, §8).
//
// Storage of record is GYBlockStore (SQLite); this class owns only the
// pasteboard polling/writing and the self-write suppression fingerprint,
// since those must stay coupled to the same changeCount bookkeeping.
//
// Keep 同步接入后，本机永远只留 20 条视图；Outbox（GYBlockStore）不受
// 20 条限制，见 MACOS-KEEP-IMPLEMENTATION-SPEC.md §3。

#import <Foundation/Foundation.h>
#import "GYBlockStore.h"

NS_ASSUME_NONNULL_BEGIN

/// New entry id, shared format with Keep: [A-Za-z0-9_-]{8,128}.
extern NSString *GYNewClipboardEntryId(void);

/// View-model over a GYBlock, kept for source compatibility with existing
/// call sites (unixTime/pendingUpload naming predates the block store).
@interface GYClipboardEntry : NSObject
@property(nonatomic, copy) NSString *entryId;
@property(nonatomic) GYBlockKind kind;
@property(nonatomic, copy) NSString *text;             // kind == GYBlockKindText
@property(nonatomic, copy, nullable) NSString *sha256;  // kind == GYBlockKindImage
@property(nonatomic) NSUInteger byteSize;               // kind == GYBlockKindImage
@property(nonatomic, copy, nullable) NSString *blobPath;
@property(nonatomic) NSTimeInterval unixTime;
/// YES only while this Mac is still trying to upload it (GYBlockStateQueued).
@property(nonatomic) BOOL pendingUpload;
+ (instancetype)fromBlock:(GYBlock *)block;
@end

@interface GYClipboardHistory : NSObject

+ (instancetype)sharedHistory;

/// 开始监听系统剪贴板（0.2s 轮询 changeCount）。幂等。
- (void)startCapture;

/// HEAD 20 view, newest/most-authoritative first.
@property(nonatomic, readonly, copy) NSArray<GYClipboardEntry *> *entries;

/// 清空本机视图（不影响 Keep；下一轮同步会把 Keep 的最新 20 条拉回来）。
- (void)clear;

/// Writes remote confirmed text to the system pasteboard, suppressing the
/// self-write fingerprint so the poll loop does not re-capture it.
- (BOOL)publishRemoteTextToSystemPasteboard:(NSString *)text;

/// Writes remote confirmed PNG image data to the system pasteboard as
/// NSPasteboardTypePNG (never downgraded to placeholder text — spec §7.3).
- (BOOL)publishRemoteImageToSystemPasteboard:(NSData *)pngData;

/// Re-publishes a HEAD entry the user clicked on in the settings panel. Does
/// not create a new Keep entry (spec §6 剪贴板页: "不创建新的 Keep 条目").
- (BOOL)republishEntryToSystemPasteboard:(GYClipboardEntry *)entry;

/// Absolute path to the local blob for an image entry, downloading it lazily
/// is GYKeepSync's job — this just resolves the path GYBlockStore already
/// has, or nil if not yet downloaded.
- (nullable NSData *)imageDataForEntry:(GYClipboardEntry *)entry;

/// 通知名：历史发生变化（新增或清空）时发出，object 为 GYClipboardHistory。
+ (NSString *)didChangeNotification;

@end

NS_ASSUME_NONNULL_END
