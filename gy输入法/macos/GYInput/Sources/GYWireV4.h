// GYWireV4 — pure parsing/validation for the Keep v4 sync protocol
// (MACOS-KEEP-IMPLEMENTATION-SPEC.md §7). No network, no ivars, no
// GYBlockStore access, so it can be unit-tested directly (see
// GYInputTests/GYWireV4Tests.m) the same way GYCandidateGridMath.h is.
//
// Field-count and validation rules mirror the Windows client
// (gy输入法/native/src/GyKeepSync.cpp ParseWireEntries) exactly, since that
// is the implementation actually interoperating with production Keep — not
// the slightly looser table in the spec doc (e.g. D lines carry no trailing
// originDeviceId field in the real wire format).

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

/// Strict, whole-payload-rejecting parser for the base64 wire-v4 body inside
/// `GET /api/clipboard/sync`'s `data.payload` field:
///   T \t sequence \t id \t capturedAtMs \t textBase64            (5 fields)
///   I \t sequence \t id \t capturedAtMs \t mime \t size \t sha256 (7 fields)
///   D \t sequence \t id                                          (3 fields)
/// Returns nil on any structural anomaly — never partially applies a
/// malformed page. Returns an empty array for an empty/absent payload.
extern NSArray<GYWireChange *> *_Nullable GYParseWireV4Payload(NSString *_Nullable base64Payload);

/// Parses `{ ok, data: { ack: { id, sequence }, cursor } }` — the response
/// to POST /api/clipboard/sync and PUT /api/clipboard/images/{id}.
extern NSString *_Nullable GYParseAckSequence(NSData *_Nullable data);

/// Parses `{ ok, data: { cursor, hasMore, payload } }` and the wire-v4 body
/// inside it. Returns nil (whole page rejected) on any structural anomaly.
extern NSArray<GYWireChange *> *_Nullable GYParseSyncPage(NSData *_Nullable data,
                                                            NSString *_Nullable *outCursor,
                                                            NSNumber *_Nullable *outHasMore);

NS_ASSUME_NONNULL_END
