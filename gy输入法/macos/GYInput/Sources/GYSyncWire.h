// GYSyncWire — pure parsing/validation for the line payloads returned by
// `GET /api/clipboard/sync`. No network, no ivars, no GYBlockStore-instance
// access, so it can be unit-tested directly (see
// GYInputTests/GYSyncWireTests.m) the same way GYCandidateGridMath.h is.
//
// ============================================================================
// NAMING — corrected 2026-08-08 after a P0 review finding. The previous
// version of this file inferred "wire-v4 is unconfirmed" from a bare 401 on
// an unauthenticated probe of /api/clipboard/sync. That was invalid: 401
// only proves the auth middleware runs before the handler inspects query
// parameters — it says nothing about whether `format=wire-v4` is recognized
// once past auth. The correct way to check is to read the server source,
// which is public in this same working tree's sibling checkout. Verified by:
//
//   git show 2bf366b:apps/keep/app/api/clipboard/sync/route.ts
//   git show 2bf366b:apps/keep/lib/clipboard-wire.ts
//
// route.ts reads `format=wire-v4` off the query string itself:
//   const v4 = url.searchParams.get("format") === "wire-v4"
//   payload: v4 ? wireSnapshotV4(...) : wireSnapshot(...)
// clipboard-wire.ts implements BOTH as real, separate functions, and its own
// comment names the default one "v3":
//   "v4 keeps v3's compact base64 envelope, but appends the opaque device ID
//    to every transition. It is opt-in: the established v3 format stays
//    byte-for-byte compatible for already released Windows and macOS
//    clients."
//
// So there are two real, distinct, both-implemented formats — not one real
// format and one aspirational one:
//
//  "v3" (no `format=` parameter; this is what today's requests use) —
//     T \t sequence \t id \t capturedAtMs \t textBase64            (5 fields)
//     I \t sequence \t id \t capturedAtMs \t mime \t size \t sha256 (7 fields)
//     D \t sequence \t id                                          (3 fields)
//
//  "v4" (`?format=wire-v4`; adds a trailing originDeviceId to every line,
//     "" when absent) —
//     T \t sequence \t id \t capturedAtMs \t textBase64 \t originDeviceId    (6 fields)
//     I \t sequence \t id \t capturedAtMs \t mime \t size \t sha256 \t originDeviceId (8 fields)
//     D \t sequence \t id \t originDeviceId                                 (4 fields)
//
// This still does NOT mean Mac should start sending `format=wire-v4`:
//   - Windows 0.10.79's shipped client never sends that parameter — it only
//     ever uses v3 — so v3 is confirmed as what actually interoperates today.
//   - Whether v4 is live on the CURRENTLY DEPLOYED Cloud Run revision is a
//     separate question from whether it exists in this source commit. The
//     deployed revision (as of this writing: `gyenbox-keep-00009-tes`,
//     traffic tag "syncv3", created 2026-08-07T22:02:39Z, confirmed via
//     `gcloud run services describe gyenbox-keep`) is tagged in a way that
//     suggests it predates the v4/device-identity commit, but the revision
//     metadata carries no git SHA, so that is inference from a human-chosen
//     tag name, not proof.
//   - Nobody has made an authenticated `?format=wire-v4` request against
//     production and inspected the response.
// GYParseSyncWireV4Payload below exists so the client is *ready* the moment
// v4 is confirmed live with a real token — GYKeepSync does not call it yet.
// ============================================================================

#import <Foundation/Foundation.h>
#import "GYBlockStore.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GYWireChangeKind) { GYWireChangeAdd, GYWireChangeDelete };

@interface GYWireChange : NSObject
@property(nonatomic) GYWireChangeKind kind;
@property(nonatomic, strong, nullable) GYBlock *block;   // kind == Add
@property(nonatomic, copy, nullable) NSString *entryId;  // kind == Delete
/// v4 only ("" on v3, and "" when the server has no origin for a line).
@property(nonatomic, copy) NSString *originDeviceId;
@end

extern BOOL GYIsValidEntryId(NSString *entryId);
/// Decimal string, 1–20 digits, non-zero. Used for ACK/wire sequences, which
/// Keep never assigns as zero.
extern BOOL GYIsDecimalSequence(NSString *value);
/// Same as GYIsDecimalSequence but allows "0" — the valid starting cursor
/// for an account with no history yet.
extern BOOL GYIsDecimalCursor(NSString *value);
extern BOOL GYIsHexSHA256(NSString *value);

/// Lowercase hex SHA-256 of `data`. Shared by GYKeepSync (verifying a
/// downloaded image against its declared hash) and GYClipboardHistory
/// (fingerprinting a captured image) — previously duplicated in both; this
/// is the one implementation now, which is also what makes it unit-testable.
extern NSString *GYSHA256Hex(NSData *data);

/// Strict, whole-payload-rejecting parser for the v3 shape (see NAMING
/// above) — the format `GET /api/clipboard/sync` actually returns today with
/// no `format=` parameter, confirmed live and confirmed as what Windows
/// 0.10.79 sends and parses. Returns nil on any structural anomaly — never
/// partially applies a malformed page. Returns an empty array for an
/// empty/absent payload. A line with a trailing originDeviceId field (the v4
/// shape) is rejected here, not tolerated — use GYParseSyncWireV4Payload for
/// that shape once it is confirmed live.
extern NSArray<GYWireChange *> *_Nullable GYParseSyncWireV3Payload(NSString *_Nullable base64Payload);

/// Same line grammar as GYParseSyncWireV3Payload, but for the v4 shape (one
/// extra trailing originDeviceId field per line). Implemented and tested so
/// the client is ready the moment v4 is confirmed live — GYKeepSync does not
/// request `format=wire-v4` yet, so this is currently unused in the running
/// app. Requires GYIsValidOriginDeviceId to be true, or empty string.
extern NSArray<GYWireChange *> *_Nullable GYParseSyncWireV4Payload(NSString *_Nullable base64Payload);

/// Parses `{ ok, data: { ack: { id, sequence }, cursor } }` — the response
/// to POST /api/clipboard/sync and PUT /api/clipboard/images/{id}.
extern NSString *_Nullable GYParseAckSequence(NSData *_Nullable data);

/// Parses `{ ok, data: { cursor, hasMore, payload } }` and the wire body
/// inside it via GYParseSyncWireV3Payload. Returns nil (whole page rejected)
/// on any structural anomaly. There is no V4 variant of this envelope parser
/// because GYKeepSync never requests the v4 payload — see NAMING above.
extern NSArray<GYWireChange *> *_Nullable GYParseSyncPage(NSData *_Nullable data,
                                                            NSString *_Nullable *outCursor,
                                                            NSNumber *_Nullable *outHasMore);

NS_ASSUME_NONNULL_END
