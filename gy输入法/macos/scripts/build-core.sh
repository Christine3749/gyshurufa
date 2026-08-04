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
if [[ -d "$root/GYInput/Resources/rime-data" ]]; then
  mkdir -p "$app/Contents/Resources"
  cp -R "$root/GYInput/Resources/rime-data" "$app/Contents/Resources/rime-data"
fi
if [[ -f "$root/GYInput/Resources/AppIcon.icns" ]]; then
  mkdir -p "$app/Contents/Resources"
  cp "$root/GYInput/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
fi
for lproj in "$root/GYInput/Resources/"*.lproj; do
  [[ -d "$lproj" ]] || continue
  cp -R "$lproj" "$app/Contents/Resources/"
done
xcrun clang++ -fobjc-arc -mmacosx-version-min=13.0 \
  -I/opt/homebrew/include \
  -framework Cocoa -framework Carbon -framework InputMethodKit \
  "$root/GYInput/Sources/main.m" \
  "$root/GYInput/Sources/GYCandidateWindow.m" \
  "$root/GYInput/Sources/GYInputController.m" \
  "$root/GYInput/Sources/GYInputMode.m" \
  "$root/GYInput/Sources/GYPreferencesController.m" \
  "$root/GYInput/Sources/GYRimeBridge.mm" \
  "$root/GYInput/Sources/GYSettingsStore.m" \
  "$root/GYInput/Sources/GYUpdateService.m" \
  -L/opt/homebrew/lib -lrime -lc++ \
  -o "$app/Contents/MacOS/GYInput"
codesign --force --sign "$identity" --timestamp=none "$app"
plutil -lint "$app/Contents/Info.plist"
codesign --verify --strict --verbose=2 "$app"
echo "Built minimal GY input core: $app"
