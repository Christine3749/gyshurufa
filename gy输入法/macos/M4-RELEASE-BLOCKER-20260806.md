# macOS Release Evidence - 2026-08-06

## Current external state

A read-only HTTPS request to `https://www.shurufa.wang/download/latest-macos.json` returned:

```json
{"error":"not_found"}
```

The macOS app now explicitly declares `GYUpdateChannel = release`, so its automatic update service correctly targets this future official manifest rather than the beta endpoint.

## What is intentionally not claimed

- No macOS PKG has been built on this Windows host.
- No Developer ID signature or Apple notarization has been verified.
- No package SHA-256 exists yet and none must be invented.
- No macOS artifact or manifest has been uploaded to `shurufa.wang`.

## Required atomic release transaction

1. On an Apple Silicon Mac, run the existing configure and build scripts.
2. Sign the input-method app with Developer ID Application credentials.
3. Build the installer with Developer ID Installer credentials.
4. Submit the PKG to Apple notarization, wait for acceptance, and staple the ticket.
5. Generate the final full SHA-256 from that exact stapled PKG.
6. Upload the PKG and `latest-macos.json` together to the official download location.
7. The manifest must contain the real `version`, numeric `build`, official HTTPS `packageURL`, and full 64-character SHA-256.
8. Fetch the public manifest and artifact again, then validate HTTP status, checksum, signature, notarization ticket, and first-install behavior on a clean Mac user account.

Until these steps have evidence, the macOS stage 3 public-download requirement remains incomplete.
