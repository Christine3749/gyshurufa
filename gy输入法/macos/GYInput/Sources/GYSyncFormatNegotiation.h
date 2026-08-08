// GYSyncFormatNegotiation — pure state transition for deciding whether the
// client may rely on the still-unconfirmed v4 wire shape (trailing
// originDeviceId — see the NAMING note in GYSyncWire.h), and for detecting
// when it must fall back to v3. No network, no ivars, so the negotiation
// rules can be unit-tested directly (see
// GYInputTests/GYSyncFormatNegotiationTests.m) instead of only being
// exercised by hand against a real, authenticated server response.
//
// GYKeepSync does not send `format=wire-v4` yet (see GYSyncWire.h), so this
// module is not wired into the live poll loop — it exists so the decision
// rule is defined and tested before that switch is flipped, not derived ad
// hoc from a live response the first time someone turns v4 on.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GYSyncFormatMode) {
  /// Only the confirmed-live v3 shape is used. The starting mode, and the
  /// only mode any shipped build has ever been in.
  GYSyncFormatV3Only,
  /// A `format=wire-v4` request has been authenticated (HTTP 200) and its
  /// response body actually parsed as the v4 shape — not just requested.
  GYSyncFormatV4Confirmed,
};

/// `currentMode`: the mode before this response.
/// `requestedV4`: whether THIS request asked for `format=wire-v4`. If NO,
///   the response says nothing about v4 support and the mode is unchanged —
///   this covers the ordinary v3-only sync rounds that make up all traffic
///   today.
/// `httpStatusCode`: the response status. Only 200 may promote or demote the
///   mode. 401/404/429/503/timeouts/etc are transient or auth conditions and
///   must never flip the protocol mode in either direction — retry next
///   round in whatever mode was already active, so a rate limit or an
///   expired token can never look like "v4 got disabled" or "v4 got
///   confirmed".
/// `responseParsesAsV4Shape` / `responseParsesAsV3Shape`: whether
///   GYParseSyncWireV4Payload / GYParseSyncWireV3Payload succeeded on the
///   actual response body. Passed in separately rather than assumed
///   mutually exclusive, so a corrupt response (matches neither) is
///   representable and handled without guessing.
///
/// Transitions:
///   200 + v4-shaped response  -> V4Confirmed  (only way to ever promote)
///   200 + v3-shaped response  -> V3Only        (explicit downgrade: the
///                                 server ignored/rejected format=wire-v4
///                                 and returned its default shape anyway)
///   200 + neither shape parses -> unchanged    (corrupt page; retry, don't
///                                 guess either way)
///   any non-200 status         -> unchanged    (transient; v3 sync always
///                                 remains available regardless)
///   requestedV4 == NO          -> unchanged    (not a v4 negotiation round)
extern GYSyncFormatMode GYNextSyncFormatMode(GYSyncFormatMode currentMode,
                                              BOOL requestedV4,
                                              NSInteger httpStatusCode,
                                              BOOL responseParsesAsV4Shape,
                                              BOOL responseParsesAsV3Shape);

NS_ASSUME_NONNULL_END
