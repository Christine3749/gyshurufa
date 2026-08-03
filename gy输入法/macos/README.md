# GY Input Method for macOS (Apple Silicon)

This directory is the Apple-Silicon-native product line for GY Input Method. It is intentionally separate from `native/`, which is the Windows TSF implementation.
## Mandatory product contract

Before changing any Mac input, candidate, mode, visual, account, or release behavior, read the repository-wide [GY Input Method Product Standard](../../GY_INPUT_METHOD_PRODUCT_STANDARD.md), [GY Visual Identity](../GY_VISUAL_IDENTITY.md), and [Platform Handoff](../../release/PLATFORM_HANDOFF.md). They are the binding cross-platform product and release baseline. macOS must reproduce the confirmed GY behavior and visual hierarchy, but must use native InputMethodKit APIs rather than porting Windows TSF implementation details.

## Current status

The project now has a native InputMethodKit controller, real arm64 librime build chain, persistent 简体／繁体／EN mode, candidate paging, local learning data, and a signed/notarized PKG pipeline. It still must be built and smoke-tested on an Apple Silicon Mac before public download; Windows cannot validate macOS signing or client compatibility.

The internal target is offline full pinyin, marked text, system candidate placement, Space/1–9/Escape/Backspace, PageUp/PageDown, standalone Shift Chinese/EN switching, Chinese punctuation, and an input-source menu for 简体／繁体／EN.

## Architecture

```text
GYInput.app (macOS input-method bundle, arm64)
  ├─ InputMethodKit: IMKServer + one GYInputController per app session
  ├─ GYRimeBridge.mm: Objective-C++ adapter to librime C API
  ├─ IMKCandidates: stable system candidate window for the first beta
  ├─ Resources/rime-data: shared schema and dictionaries (read-only)
  └─ ~/Library/Application Support/GYInput/rime: user learning data
```

No text is sent to a network service in the input path. Account, AI, and cross-device sync are explicitly outside the first M1 milestone.

## On an M1 Mac

1. Install current Xcode command-line tools, XcodeGen, and the dependencies needed by the bundled librime source.
2. From this directory, run `./scripts/build-macos.sh`.
3. Run `./scripts/smoke-test-macos.sh`, then test `.build/DerivedData/Build/Products/Release/GYInput.app` in TextEdit, Safari, Chrome, VS Code, WeChat, Word, Slack, and Terminal.
4. Add it in System Settings > Keyboard > Input Sources for internal testing.

Public release only: set `GY_DEVELOPER_IDENTITY`, `GY_INSTALLER_IDENTITY`, and `GY_NOTARY_PROFILE`, then run `./scripts/package-release.sh`. It produces a notarized PKG for `/Library/Input Methods` and SHA-256 file; only that verified artifact may be uploaded to the official download origin.
After all package checks pass, run `./scripts/publish-r2.sh`. It revalidates the SHA-256, installer signature, Gatekeeper assessment, and notarization staple before uploading; the public paths are `/download/latest.pkg` and `/download/latest.pkg.sha256`.


Read [M1_ROADMAP.md](M1_ROADMAP.md) before implementing the next milestone.
