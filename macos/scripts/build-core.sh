#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/build/GYInput.app"
identity="${GY_DEVELOPMENT_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)"
fi
[[ -n "$identity" ]] || { echo "Apple Development certificate not found." >&2; exit 1; }
"$root/scripts/verify-input-source-contract.sh" "$root/GYInput/Resources/Info.plist"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$root/GYInput/Resources/Info.plist" "$app/Contents/Info.plist"
"$root/scripts/verify-input-source-contract.sh" "$app/Contents/Info.plist"
xcrun clang -fobjc-arc -mmacosx-version-min=13.0 \
  -framework Cocoa -framework Carbon -framework InputMethodKit \
  "$root/GYInput/Sources/main.m" "$root/GYInput/Sources/GYInputController.m" \
  -o "$app/Contents/MacOS/GYInput"
codesign --force --sign "$identity" --timestamp=none "$app"
plutil -lint "$app/Contents/Info.plist"
codesign --verify --strict --verbose=2 "$app"
echo "Built minimal GY input core: $app"
