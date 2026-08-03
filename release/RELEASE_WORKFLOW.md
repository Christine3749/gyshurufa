# GY unified release workflow

`release/release.json` is the only release truth for Windows, macOS, the website, and the download Worker. A released version is immutable: never replace an existing file under `releases/<version>/`.

## Required order

1. Start a new version in `release/release.json`. `version`, `coreVersion`, and `hostVersion` must match exactly.
2. Windows: configure with `-DGY_VERSION=<version>`, build DLL and Host, run `ctest -C Release`, build the setup EXE, verify its SHA-256 and version.
3. macOS on Apple Silicon: `git pull --ff-only origin main`; build with `GY_RELEASE_VERSION=<version>`; sign with Developer ID; notarize and staple; run the input smoke test; update only the macOS fields in the canonical manifest.
4. Upload immutable files only: `releases/<version>/windows/` and `releases/<version>/macos/`. Verify byte size and SHA-256 after upload.
5. Run the release Worker and site build tests. The Worker refuses to expose `latest` until both platform entries are verified and macOS is signed and notarized.
6. Run the full security scan only after all code and artifacts are final.
7. A single release command advances `releases/latest.json` last. If any gate fails, do not advance it.

## Upgrade truth on Windows

Install success has three states: package copied and hash checked; Host switched and reports the requested version; and TSF core DLL activated in applications that currently accept input.

Existing Chrome, WeChat, ChatGPT, VS Code, and other input processes may keep the old DLL loaded. The installer must say: **close and reopen input applications; restart Windows only if the core version is still old**. It must never claim activation completed before that.

## Two-computer Git rule

- Both computers use the same GitHub remote and branch protection.
- Before work: `git pull --ff-only origin main`.
- No direct overwrite of `main`; commit a focused branch and merge after checks.
- The Mac computer never deploys the Worker. It uploads only its immutable package and commits the verified macOS manifest fields.
- The Windows/release computer only advances `latest` after pulling that commit and passing all gates.

## Prohibited actions

- Reusing a released version number.
- Manually editing `latest.json` to bypass validation.
- Hard-coding a version, hash, file name or download URL in the website or Worker.
- Publishing an unsigned Windows stable package or an unsigned/unnotarized macOS package.
