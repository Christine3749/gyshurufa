#import "GYSyncFormatNegotiation.h"

GYSyncFormatMode GYNextSyncFormatMode(GYSyncFormatMode currentMode,
                                      BOOL requestedV4,
                                      NSInteger httpStatusCode,
                                      BOOL responseParsesAsV4Shape,
                                      BOOL responseParsesAsV3Shape) {
  if (!requestedV4) return currentMode;
  if (httpStatusCode != 200) return currentMode;
  // An empty payload (nothing new to sync) is valid input to BOTH
  // GYParseSyncWireV3Payload and GYParseSyncWireV4Payload — both return an
  // empty array, i.e. both flags can legitimately be YES at once on a
  // perfectly ordinary, empty response. That is ambiguous, not confirming:
  // it must not promote to v4 (there is no v4-specific evidence at all) and
  // must not demote out of an already-confirmed v4 (no v3-specific evidence
  // either). Only an UNAMBIGUOUS match — one shape succeeds and the other
  // does not — is decisive.
  if (responseParsesAsV4Shape && !responseParsesAsV3Shape) return GYSyncFormatV4Confirmed;
  if (responseParsesAsV3Shape && !responseParsesAsV4Shape) return GYSyncFormatV3Only;
  return currentMode;
}
