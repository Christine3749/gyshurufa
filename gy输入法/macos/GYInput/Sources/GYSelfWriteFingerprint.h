// GYSelfWriteFingerprint — pure decision function for GYClipboardHistory's
// self-write suppression race. No pasteboard, no ivars, so the race case can
// be unit-tested directly instead of only by hand against the real system
// pasteboard (see GYInputTests/GYSelfWriteFingerprintTests.m).

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// After GYClipboardHistory writes remote content to the system pasteboard,
/// the 0.2s poll loop must tell "the write I just made" apart from "a real
/// user copy that happened to land on the very next poll tick" — see
/// MACOS-KEEP-IMPLEMENTATION-SPEC.md 附录 A, incident C-03. Suppressing by
/// changeCount alone is wrong: the user could ⌘C in the race window between
/// the write and the next poll, landing on the same changeCount with
/// genuinely different content, and that copy must not be swallowed.
///
/// Returns YES only when the observation is indistinguishable from our own
/// last write: matching changeCount AND an identical fingerprint (raw text
/// for a text write, SHA-256 for an image write). Any mismatch — including
/// same changeCount but different content — returns NO, so the capture path
/// treats it as a real new copy.
extern BOOL GYIsOwnPasteboardWrite(NSString *_Nullable selfWrittenFingerprint,
                                    NSInteger selfWrittenChangeCount,
                                    NSString *_Nullable observedFingerprint,
                                    NSInteger observedChangeCount);

NS_ASSUME_NONNULL_END
