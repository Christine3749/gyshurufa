// GYSyncWire — pure parsing/validation for the line payload returned by
// `GET /api/clipboard/sync` (no `format=` query parameter). No network, no
// ivars, no GYBlockStore access, so it can be unit-tested directly (see
// GYInputTests/GYSyncWireTests.m) the same way GYCandidateGridMath.h is.
//
// ============================================================================
// NAMING — there are THREE distinct wire formats in play; do not conflate
// them under one name ("wire-v4"), because they are not confirmed identical:
//
//  1. "wire" (legacy, flat) — `GET /api/clipboard?format=wire`. 3 tab-
//     separated fields per line: id, capturedAtMs, textBase64. No sequence,
//     no cursor, text-only. This is what the pre-2026-08-08 Mac client used
//     and is presumably still served for old clients; this file has nothing
//     to do with it.
//
//  2. The format parsed HERE — the payload `GET /api/clipboard/sync` (with
//     `?cursor=N` or `?snapshot=1`, and critically NO `format=` parameter at
//     all) actually returns today. 5/7/3 tab-separated fields for T/I/D —
//     see GYParseSyncWirePayload below. This is confirmed live by direct
//     cross-reference against the Windows 0.10.79 client
//     (native/src/GyKeepSync.cpp FetchPage/ParseWireEntries), which also
//     never sends a `format=` parameter and successfully parses this exact
//     shape against production keep.gyenbox.com. Both Mac and Windows speak
//     this format today; that is the actual interop contract.
//
//  3. "wire-v4" as MACOS-KEEP-IMPLEMENTATION-SPEC.md §7.4 describes it —
//     requested with an explicit `&format=wire-v4` query parameter, and with
//     a wider line shape that adds a trailing originDeviceId field (6/8/4
//     fields for T/I/D, not 5/7/3). Neither Mac nor Windows' shipped client
//     ever sends `format=wire-v4` in a request. Whether the server even
//     recognizes that parameter, and whether its output would match #2 or
//     add the extra field, is UNCONFIRMED — nobody has probed it with a
//     valid token. Do not assume it is the same as #2.
//
// This file/parser implements and is named after #2 — the format actually in
// production use — not #3. If #3 is ever confirmed live and turns out to
// differ (e.g. the extra originDeviceId field), it needs its own parser and
// its own name, not a silent extension of this one.
// ============================================================================

#import <Foundation/Foundation.h>
#import "GYBlockStore.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GYWireChangeKind) { GYWireChangeAdd, GYWireChangeDelete };

@interface GYWireChange : NSObject
@property(nonatomic) GYWireChangeKind kind;
@property(nonatomic, strong, nullable) GYBlock *block;   // kind == Add
@property(nonatomic, copy, nullable) NSString *entryId;  // kind == Delete
@end

extern BOOL GYIsValidEntryId(NSString *entryId);
/// Decimal string, 1–20 digits, non-zero. Used for ACK/wire sequences, which
/// Keep never assigns as zero.
extern BOOL GYIsDecimalSequence(NSString *value);
/// Same as GYIsDecimalSequence but allows "0" — the valid starting cursor
/// for an account with no history yet.
extern BOOL GYIsDecimalCursor(NSString *value);
extern BOOL GYIsHexSHA256(NSString *value);

/// Strict, whole-payload-rejecting parser for the base64 body inside
/// `GET /api/clipboard/sync`'s `data.payload` field (format #2 above, no
/// `format=` query parameter):
///   T \t sequence \t id \t capturedAtMs \t textBase64            (5 fields)
///   I \t sequence \t id \t capturedAtMs \t mime \t size \t sha256 (7 fields)
///   D \t sequence \t id                                          (3 fields)
/// A line with a trailing originDeviceId field (the spec's "wire-v4" shape,
/// #3 above) is rejected, not tolerated — see the NAMING note. Returns nil on
/// any structural anomaly — never partially applies a malformed page. Returns
/// an empty array for an empty/absent payload.
extern NSArray<GYWireChange *> *_Nullable GYParseSyncWirePayload(NSString *_Nullable base64Payload);

/// Parses `{ ok, data: { ack: { id, sequence }, cursor } }` — the response
/// to POST /api/clipboard/sync and PUT /api/clipboard/images/{id}.
extern NSString *_Nullable GYParseAckSequence(NSData *_Nullable data);

/// Parses `{ ok, data: { cursor, hasMore, payload } }` and the wire body
/// inside it (via GYParseSyncWirePayload). Returns nil (whole page rejected)
/// on any structural anomaly.
extern NSArray<GYWireChange *> *_Nullable GYParseSyncPage(NSData *_Nullable data,
                                                            NSString *_Nullable *outCursor,
                                                            NSNumber *_Nullable *outHasMore);

NS_ASSUME_NONNULL_END
