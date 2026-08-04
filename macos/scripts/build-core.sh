#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/build/GYInput.app"
manifest="$root/../release/release.json"
rime_prefix="${GY_RIME_PREFIX:-$root/build/rime-runtime-macos13-arm64}"
rime_shared="$root/../native/runtime/rime/shared"
opencc_data="$rime_prefix/share/opencc"
logo="$root/../native/installer/assets/gy-tray-icon.svg"
recovery="$root/scripts/GYRecovery.sh"
identity="${GY_DEVELOPMENT_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)"
fi
[[ -n "$identity" ]] || { echo "Apple Development certificate not found." >&2; exit 1; }
[[ -f "$manifest" ]] || { echo "Release manifest not found: $manifest" >&2; exit 1; }
[[ -f "$rime_prefix/lib/librime.1.dylib" ]] || "$root/scripts/build-rime-runtime.sh"
[[ -f "$rime_prefix/lib/librime.1.dylib" ]] || { echo "macOS 13 Rime runtime is required." >&2; exit 1; }
[[ -f "$rime_shared/gy_pinyin.schema.yaml" ]] || { echo "Shared GY Rime data is missing." >&2; exit 1; }
[[ -f "$opencc_data/t2s.json" ]] || { echo "OpenCC conversion data is required." >&2; exit 1; }
[[ -f "$logo" ]] || { echo "Shared GY logo is missing." >&2; exit 1; }
[[ -x "$recovery" ]] || { echo "GY recovery helper is missing." >&2; exit 1; }
release_version="$(/usr/bin/plutil -extract version raw -o - "$manifest")"
plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$root/GYInput/Resources/Info.plist")"
[[ "$release_version" == "$plist_version" ]] || { echo "Info.plist version must match release/release.json." >&2; exit 1; }
"$root/scripts/verify-input-source-contract.sh" "$root/GYInput/Resources/Info.plist"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources/Rime"
cp "$root/GYInput/Resources/Info.plist" "$app/Contents/Info.plist"
iconset="$app/Contents/Resources/GYIcon.iconset"
mkdir "$iconset"
sips -s format png -z 1024 1024 "$logo" --out "$iconset/icon_512x512@2x.png" >/dev/null
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$iconset/icon_512x512@2x.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
done
for size in 16 32 128 256; do
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" "$iconset/icon_512x512@2x.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/GYIcon.icns"
rm -rf "$iconset"
ditto "$rime_shared" "$app/Contents/Resources/Rime/shared"
ditto "$opencc_data" "$app/Contents/Resources/Rime/shared/opencc"
cp "$recovery" "$app/Contents/Resources/GYRecovery.sh"
"$root/scripts/verify-input-source-contract.sh" "$app/Contents/Info.plist"
xcrun clang++ -fobjc-arc -mmacosx-version-min=13.0 -I "$rime_prefix/include" \
  -framework Cocoa -framework Carbon -framework InputMethodKit \
  "$root/GYInput/Sources/main.m" "$root/GYInput/Sources/GYInputController.m" \
  "$root/GYInput/Sources/GYCandidatePanel.m" \
  "$root/GYInput/Sources/GYDiagnostics.m" "$root/GYInput/Sources/GYInputMode.m" \
  "$root/GYInput/Sources/GYRimeRuntime.mm" "$root/GYInput/Sources/GYRimeSession.mm" \
  "$rime_prefix/lib/librime.1.dylib" -Wl,-rpath,@executable_path/../Frameworks -o "$app/Contents/MacOS/GYInput"

cp -L "$rime_prefix/lib/librime.1.dylib" "$app/Contents/Frameworks/librime.1.dylib"
install_name_tool -id '@rpath/librime.1.dylib' "$app/Contents/Frameworks/librime.1.dylib"
codesign --force --sign "$identity" --timestamp=none "$app/Contents/Frameworks/librime.1.dylib"
codesign --force --sign "$identity" --timestamp=none "$app"
plutil -lint "$app/Contents/Info.plist"
codesign --verify --strict --verbose=2 "$app"
"$root/scripts/verify-bundled-runtime.sh" "$app"
echo "Built GY macOS input core $release_version: $app"
