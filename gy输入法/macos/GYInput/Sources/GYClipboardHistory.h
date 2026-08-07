// GYClipboardHistory — 本机剪贴板历史（与 Windows 端同一产品契约）。
//
// 契约要点（CROSS-PLATFORM-CONTRACT.md §4 / CLIPBOARD-PAGE-DESIGN.md）：
// - 最近 20 条纯文本，先进后出（最新在最前）。
// - 单条最大 1 MiB（按 UTF-8 字节计），超限直接丢弃。
// - 连续去重：与最新一条完全相同则忽略。
// - 落盘：~/Library/Application Support/GYInput/clipboard-history.tsv，
//   与 Windows 相同的转义与行格式（最旧在前）。
//
// Keep 同步接入后，行格式从 <unix_ts>\t<escaped> 升级为
// <id>\t<unix_ts>\t<pending>\t<escaped>；读取时兼容旧的两字段行。
// 本机始终只留 20 条，Keep 不设上限——淘汰第 21 条只影响本机。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 新的条目 ID，形如 [A-Za-z0-9_-]{8,128}，与 Keep 共用同一标识。
extern NSString *GYNewClipboardEntryId(void);

@interface GYClipboardEntry : NSObject
@property(nonatomic, copy) NSString *text;
@property(nonatomic) NSTimeInterval unixTime;
/// 与 Keep 共享的条目标识；旧格式读入时补发。
@property(nonatomic, copy) NSString *entryId;
/// YES 表示 Keep 尚未确认收到。远端来的条目永远为 NO。
@property(nonatomic) BOOL pendingUpload;
@end

@interface GYClipboardHistory : NSObject

+ (instancetype)sharedHistory;

/// 开始监听系统剪贴板（0.5s 轮询 changeCount）。幂等。
- (void)startCapture;

/// 最新在最前，最多 20 条。
@property(nonatomic, readonly, copy) NSArray<GYClipboardEntry *> *entries;

- (void)clear;

/// 用 Keep 的最新投影整体替换本机历史（校验、去重、截断到 20 条后落盘）。
- (BOOL)replaceEntries:(NSArray<GYClipboardEntry *> *)entries;

/// 把远端文本写入系统剪贴板，并吞掉自己造成的 changeCount 变化，
/// 使轮询不会把它当成一次新的用户复制再上传回 Keep。
- (BOOL)publishRemoteTextToSystemPasteboard:(NSString *)text;

/// 通知名：历史发生变化（新增或清空）时发出，object 为 GYClipboardHistory。
+ (NSString *)didChangeNotification;

@end

NS_ASSUME_NONNULL_END
