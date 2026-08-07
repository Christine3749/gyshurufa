// GYClipboardHistory — 本机剪贴板历史（与 Windows 端同一产品契约）。
//
// 契约要点（CROSS-PLATFORM-CONTRACT.md §4 / CLIPBOARD-PAGE-DESIGN.md）：
// - 最近 20 条纯文本，先进后出（最新在最前）。
// - 单条最大 1 MiB（按 UTF-8 字节计），超限直接丢弃。
// - 连续去重：与最新一条完全相同则忽略。
// - 落盘：~/Library/Application Support/GYInput/clipboard-history.tsv，
//   与 Windows 相同的转义与行格式（<unix_ts>\t<escaped>\n，最旧在前）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GYClipboardEntry : NSObject
@property(nonatomic, copy) NSString *text;
@property(nonatomic) NSTimeInterval unixTime;
@end

@interface GYClipboardHistory : NSObject

+ (instancetype)sharedHistory;

/// 开始监听系统剪贴板（0.5s 轮询 changeCount）。幂等。
- (void)startCapture;

/// 最新在最前，最多 20 条。
@property(nonatomic, readonly, copy) NSArray<GYClipboardEntry *> *entries;

- (void)clear;

/// 通知名：历史发生变化（新增或清空）时发出，object 为 GYClipboardHistory。
+ (NSString *)didChangeNotification;

@end

NS_ASSUME_NONNULL_END
