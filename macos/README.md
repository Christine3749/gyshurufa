# GY Input Method for macOS (Apple Silicon)

This directory is the Apple-Silicon-native product line for GY Input Method. It is intentionally separate from `native/`, which is the Windows TSF implementation.

## Current status

The project now has a native InputMethodKit controller, real arm64 librime build chain, persistent 简体／繁体／EN mode, candidate paging, local learning data, and a Developer ID notarized-release pipeline. The current 0.9.36 beta has been built and smoke-tested on Apple Silicon, but is deliberately **not** a Developer ID-signed or notarized public release. Windows cannot validate macOS signing or client compatibility.

The internal target is offline full pinyin, marked text, a custom Windows-aligned candidate panel (five candidates per collapsed row; a fixed 5 × 5 expanded grid), Space/1–5/Escape/Backspace, PageUp/PageDown, direct keyboard ↓ expansion and arrow navigation, standalone Shift Chinese/EN switching, Chinese punctuation, and an input-source menu for 简体／繁体／EN.

## Architecture

```text
GYInput.app (macOS input-method bundle, arm64)
  ├─ InputMethodKit: IMKServer + one GYInputController per app session
  ├─ GYRimeBridge.mm: Objective-C++ adapter to librime C API
  ├─ GYCandidatePanel: five-cell candidate row, fixed 5 × 5 expansion, paging and mode entry
  ├─ GYPreferencesController: Windows-aligned local settings panel
  ├─ Resources/rime-data: shared schema and dictionaries (read-only)
  └─ ~/Library/Application Support/GYInput/rime: user learning data
```

No text is sent to a network service in the input path. Account, AI, and cross-device sync are explicitly outside the first M1 milestone.

## On an M1 Mac

1. Install the current full Xcode app (Command Line Tools alone are insufficient), open it once to accept its licence, and select it with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
2. Install XcodeGen and the dependencies needed by the bundled librime source (for example, `brew install xcodegen`).
3. From this directory, run `./scripts/configure-m1.sh`, `./scripts/build-macos.sh`, and `./scripts/smoke-test-macos.sh` in that order.
4. Install the build with `./scripts/install-local-macos.sh --user`, then add **GY输入法** in System Settings > Keyboard > Input Sources.
5. Test in TextEdit, Safari, Chrome, VS Code, WeChat, Word, Slack, and Terminal.

### Local install and update

For local M1 testing, install to the current user only:

```bash
./scripts/install-local-macos.sh --user
```

For a machine-wide test, use the system location only. If a previous
user-level test copy exists, this explicit form moves it to Trash before the
administrator copy is installed, avoiding two bundles with the same ID:

```bash
./scripts/install-local-macos.sh --system --replace-user-copy
```

The installer first stages and validates the new system bundle, then replaces
the old system bundle, and only then archives a duplicate user copy. If a
previous run was interrupted after moving the user copy, rerun the same command
to finish the system update; do not install a second user copy alongside it.
It also removes stale LaunchServices registrations for the build product and
any archived copy before registering the one installed bundle.

Before enabling GY in System Settings, verify the result without changing it:

```bash
./scripts/check-local-install-macos.sh
```

After an update, close any candidate panel, rerun the same install command,
then switch away from GY and back to **GY输入法**. Do not keep both
`~/Library/Input Methods/GYInput.app` and `/Library/Input Methods/GYInput.app`:
Safari and other AppKit/WebKit clients may resolve the duplicate bundles to
different input-method servers.

To uninstall, first switch to a system input source. Move only the chosen
install location to Trash, then unregister by signing out and back in. User
learning and settings remain at `~/Library/Application Support/GYInput` until
the user explicitly chooses to remove them.

Use [M1_BETA_TEST_PLAN.md](M1_BETA_TEST_PLAN.md) for installation, update, uninstall, and the required cross-application evidence. Do not call the build releasable until every P0 gate in that plan has passed.

Public release only: set `GY_DEVELOPER_IDENTITY`, `GY_INSTALLER_IDENTITY`, and `GY_NOTARY_PROFILE`, then run `./scripts/package-release.sh`. It produces a notarized PKG for `/Library/Input Methods` and SHA-256 file; only that verified artifact may be uploaded to the official download origin.
After all package checks pass, run `./scripts/publish-r2.sh`. It revalidates the SHA-256, installer signature, Gatekeeper assessment, and notarization staple before uploading; the public paths are `/download/latest.pkg` and `/download/latest.pkg.sha256`.


Read [M1_ROADMAP.md](M1_ROADMAP.md) before implementing the next milestone.
