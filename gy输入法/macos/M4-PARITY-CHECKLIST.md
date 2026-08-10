# macOS Stage 4 Parity Checklist

Status: implementation is in progress. No macOS build, signing, notarization, or release upload has been performed from this Windows workspace.

## Implemented foundations

- The controller starts the isolated `GYRimeRuntime` warm session according to the persisted warm-start setting.
- Clipboard history capture is started from each input controller and uses the existing local persistent store.
- Candidate-window anchoring prefers the screen containing the caret and clamps implausible coordinate jumps.
- Candidate cards use measured one-to-four-line heights instead of a fixed two-line height.
- Rime workspace deployment uses a staged SHA-256 fingerprinted replacement for bundled build artifacts while preserving user data.
- `GYCandidateGovernance` owns candidate ordering and commit ownership:
  - Local custom phrases appear before Rime candidates when they are not already present in the Rime list.
  - A custom phrase that duplicates a Rime candidate uses the Rime commit path.
  - Every visible Rime candidate retains its filtered display index for `GYRimeBridge` translation.
  - All local phrases, not only the first phrase, commit directly and clear the active composition.

## Required Apple Silicon validation

1. Run `macos/scripts/configure-m1.sh` on a real Apple Silicon Mac.
2. Build with `macos/scripts/build-macos.sh`.
3. Verify Simplified, Traditional, English, Shift toggling, Escape, Backspace, punctuation, and partial Rime commits.
4. Add at least two custom phrases for one code and verify first/second phrase selection, number keys, mouse selection, duplicate-Rime phrases, PageUp, and PageDown.
5. Verify candidate anchoring across two displays, text fields near each screen edge, scrolling applications, and line wraps.
6. Verify clipboard history after restart, one-line through four-line cards, delete/clear behavior, and all three related settings.
7. Toggle warm start, restart the input method, and confirm that a disabled warm session is released and an enabled one is recreated.

## Release gate

- Do not create or upload a PKG until the Apple Silicon build and the validation matrix pass.
- For a normal-download experience, use the existing package script with a Developer ID Application identity, a Developer ID Installer identity, and a notarization keychain profile.
- Upload to `shurufa.wang` only after the signed and stapled PKG hash, version metadata, and release manifest are produced on macOS.

## Known boundaries

- Cross-device clipboard sync remains a product placeholder on both platforms until GY Link exists; the local sync setting must not be represented as live remote synchronization.
- The old `GYSettingsStore` string-only merge helper remains for compatibility. New controller paths use `GYCandidateGovernance` so they retain selection ownership and Rime index mapping.
