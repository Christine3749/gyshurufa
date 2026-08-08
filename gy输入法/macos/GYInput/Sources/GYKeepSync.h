#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Background bridge between the local block store (GYBlockStore) and the
/// account's Keep clipboard stream — the v4 protocol (POST/GET
/// /api/clipboard/sync, PUT/GET /api/clipboard/images/{id}) that Windows
/// 0.10.79 already speaks against keep.gyenbox.com. See
/// MACOS-KEEP-IMPLEMENTATION-SPEC.md §7.
///
/// Everything here runs off a private serial queue. Nothing on this class may
/// be reached from the composition, candidate or Rime paths — typing must
/// never wait on the network.
@interface GYKeepSync : NSObject

+ (instancetype)sharedSync;

/// Starts the poll loop and subscribes to local clipboard changes. Idempotent.
- (void)start;

/// Requests an immediate round. Ignored while one is already in flight.
- (void)wake;

/// Mirrors the 「Keep 同步」 switch.
- (void)setEnabled:(BOOL)enabled;

/// Mirrors the 「复制即粘贴」 switch. Turning it back on lets the current
/// remote head reach the system pasteboard once.
- (void)setInstantPasteEnabled:(BOOL)enabled;

/// Call after login or logout so the next round re-seeds instead of pasting
/// the previous account's newest entry, and so cursor/outbox state does not
/// leak between accounts.
- (void)accountDidChange;

@end

NS_ASSUME_NONNULL_END
