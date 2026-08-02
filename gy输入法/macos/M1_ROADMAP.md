# GY macOS M1 roadmap

## Product decision

Build a native Apple Silicon input method for macOS 13+ using InputMethodKit and Objective-C++. Do not port the Windows TSF DLL, named pipes, candidate window, installer, or `settings.ini` code. Reuse only portable product assets: librime, Rime schemas/dictionaries, local learning semantics, GY visual tokens, and future account/sync contracts.

Apple's InputMethodKit creates an `IMKInputController` per client input session; `IMKServer` owns the client connections. `IMKCandidates` is the stable baseline for candidates and selection callbacks. The M1 MVP therefore keeps Rime and the controller in the input-method process and uses the system candidate window first. A custom GY panel comes only after compatibility has been proven.

## Scope and non-goals

| Included in M1 Beta | Explicitly later |
|---|---|
| Offline full pinyin, Rime dictionaries, marked text, five visible candidates, paging | AI rewrite, cloud inference, account login |
| Space, 1–5, Escape, Backspace, arrows, Shift Chinese/English | Cross-device clipboard and personal dictionary sync |
| Local learning, short phrases, deep/light appearance choice | iOS, Mac App Store distribution, custom candidate renderer |
| arm64 build, Developer ID signature, notarized DMG/PKG, uninstall | Intel universal binary and automatic in-place engine updates |

## Delivery stages

### M0 — foundation (complete when the skeleton is accepted)

- `macos/` owns the Mac code; no Windows source is imported into the target.
- `project.yml` pins arm64 and macOS 13.0.
- Objective-C++ bridge boundary is the only location that may call `rime_api.h`.
- Shared schemas are staged into the app bundle; user data lives under `~/Library/Application Support/GYInput/rime`.
- Build scripts must refuse non-arm64 machines unless `GY_ALLOW_UNIVERSAL=1` is intentionally set.

### M1 — input demo

Acceptance:

- typing `nihao`, then Space commits `你好` in TextEdit;
- marked text updates without duplicated characters;
- 1–5 and Space commit exactly the displayed candidate; Escape cancels; Backspace edits composition;
- Ctrl/Cmd/Option shortcuts pass through untouched; a standalone Shift changes the current GY mode;
- no network connection is opened while composing;
- Rime initial deploy works for a newly created macOS user account.

### M2 — usable internal build

Acceptance:

- PageUp/PageDown, `-`/`=` or chosen equivalent page candidates consistently; no hidden selectable candidate;
- candidate window follows the system insertion point and is readable in light/dark appearances;
- local learning, short phrases, clear/backup/restore data work;
- a small Settings app controls only real settings (language mode, candidate size/theme, phrases, learning data);
- regression matrix passes: TextEdit, Safari, Chrome, VS Code, WeChat, Microsoft Word, Slack, Terminal, and a sandboxed app.

### M3 — external beta

Acceptance:

- M1 clean-install, upgrade, downgrade/rollback, and uninstall are tested;
- all bundled executable code and `librime` are signed in dependency order with hardened runtime;
- a Developer ID-signed DMG or PKG is notarized and stapled; `spctl` and `codesign --verify --strict` pass;
- crash/privacy policy and a reproducible compatibility report are published;
- no unsigned or self-signed public installer is called a release.

## Engineering boundaries

```text
InputMethodKit controller         platform-specific; owns key event policy and text client calls
GYRimeBridge (Objective-C++)      portable C++/C API boundary; owns one Rime session per controller
Rime schemas + dictionaries       reusable data, immutable in bundle
User Rime data                    per macOS account, writable and never embedded in update package
Settings data                     platform-neutral JSON contract; separate from Rime internals
Account / AI / sync               separate process/service, not callable during composition
```

## Risks to resolve before Beta

1. **Rime arm64 packaging.** Build and link the exact librime revision on a clean M1. Do not copy a Windows DLL or an unverified `.dylib` into the bundle.
2. **Client compatibility.** Browser/Electron clients often expose text ranges differently. Test marked text and cancellation in every M2 application.
3. **Update safety.** The input-method bundle can be loaded by client apps. Treat core-bundle updates as "close affected apps or log out to complete"; do not terminate user applications.
4. **Distribution trust.** Direct download requires Developer ID signing, hardened runtime, notarization, and stapling. App Sandbox is required for Mac App Store delivery but not for direct Developer ID delivery; decide it after the input-method entitlement and storage test.

## What is already reusable from Windows

- `native/third_party/librime` source and its licensing review;
- `native/runtime/rime` schema/dictionary assets;
- the product-level behavior: offline conversion, short phrases and local learning;
- GY visual specifications, release manifest ideas, test scenarios, and privacy boundary.

## What is not complete on Windows

Windows is a credible native MVP, not a finished 9/10 public product. The remaining release gates are real-application regression evidence, final signing certificate, signed package verification, and external beta feedback. Those gates do not block M0/M1 Mac work, but they must be met before calling either platform "fully complete".
