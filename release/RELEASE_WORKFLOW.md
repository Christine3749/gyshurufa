# GY unified release workflow

`release/release.json` is the only release truth for Windows, macOS, the website, and the download Worker. Each platform owns an independent immutable version stream: Windows may be `0.9.40` while macOS is `2.0.1`. Never replace an existing object under `releases/<platform>/<version>/`.

## Required order

1. Start a new version in `release/release.json`. For Windows, `version`, `coreVersion`, and `hostVersion` must match exactly. macOS has its own version, signing and notarization status.
2. Windows: configure with `-DGY_VERSION=<version>`, build DLL and Host, run `ctest -C Release`, build the setup EXE, verify its SHA-256 and version.
3. macOS on Apple Silicon: `git pull --ff-only origin main`; build with `GY_RELEASE_VERSION=<version>`; sign with Developer ID; notarize and staple; run the input smoke test; update only the macOS fields in the canonical manifest.
4. Upload immutable files only: `releases/windows/<version>/` and `releases/macos/<version>/`. Verify byte size and SHA-256 after upload.
5. Run the release Worker and site build tests. The Worker exposes each platform's `latest` only after that platform's own artifact is verified; an unfinished Mac package must never block a verified Windows release, or vice versa.
6. Run the full security scan only after all code and artifacts are final.
7. The platform-specific release command advances only its verified pointer (`releases/windows/latest.json` or `releases/macos/latest.json`) last. If that platform's gate fails, do not advance its pointer.

## Upgrade truth on Windows

Install success has three states: package copied and hash checked; Host switched and reports the requested version; and TSF core DLL activated in applications that currently accept input.

Existing Chrome, WeChat, ChatGPT, VS Code, and other input processes may keep the old DLL loaded. The installer must say: **close and reopen input applications; restart Windows only if the core version is still old**. It must never claim activation completed before that.

## Two-computer Git rule

- Both computers use the same GitHub remote and branch protection.
- Before work: `git pull --ff-only origin main`.
- No direct overwrite of `main`; commit a focused branch and merge after checks.
- The Mac computer never deploys the Worker. It uploads only its immutable package and commits the verified macOS manifest fields.
- The Windows/release computer advances only the Windows pointer after pulling that commit and passing Windows gates. The Mac release owner follows the same rule for the macOS pointer.

## Prohibited actions

- Reusing a released version number.
- Manually editing a platform `latest.json` to bypass validation.
- Hard-coding a version, hash, file name or download URL in the website or Worker.
- Publishing an unsigned Windows stable package or an unsigned/unnotarized macOS package.
