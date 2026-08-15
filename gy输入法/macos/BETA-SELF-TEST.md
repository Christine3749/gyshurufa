# macOS Beta Self-Test Delivery

This path is intentionally for self-testing only. It does not claim Developer ID signing, Apple notarization, or production-grade Gatekeeper behavior. It is isolated from `releases/latest.json`, Windows releases, and the production macOS update channel.

## One-time Cloudflare login on the Mac

```bash
cd /absolute/path/to/gy输入法/native/release-service
npx wrangler login
```

Complete the browser authorization with the Cloudflare account that owns `gy-shurufa-releases` and the `shurufa.wang` Worker route.

## Build, package, and publish the Beta

1. Run the existing macOS configure and build scripts.
2. Locate the produced `GYInput.app` bundle.
3. Run:

```bash
cd /absolute/path/to/gy输入法
bash macos/scripts/package-beta.sh "/absolute/path/to/GYInput.app" "$PWD/release/macos-beta"
bash macos/scripts/publish-beta-r2.sh \
  "$PWD/release/macos-beta/GYInput-<version>-arm64.pkg" \
  "$PWD/release/macos-beta/macos-beta.json"
```

The publisher deploys the Worker route, uploads the exact PKG to an immutable Beta key, uploads its matching metadata, and fetches the public feed again.

## Public Beta URLs

```text
https://www.shurufa.wang/download/macos-beta.json
https://www.shurufa.wang/download/beta/macos/<version>/download
```

## Install only on your own test Mac

An unsigned download can be quarantined. After downloading, run:

```bash
xattr -dr com.apple.quarantine "$HOME/Downloads/GYInput-<version>-arm64.pkg"
sudo installer -pkg "$HOME/Downloads/GYInput-<version>-arm64.pkg" -target /
```

Then add or enable `输入法.网` in macOS Input Sources and test typing, candidate selection, preferences, restart behavior, and update checks.

Never present this unsigned path as a public production release. Switch back to the `release` channel only after Developer ID signing and Apple notarization are available.