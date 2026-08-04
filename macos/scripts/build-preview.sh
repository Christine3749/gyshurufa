#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plist="$root/GYInputPreview/Resources/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
release="$root/build/preview-$version"; app="$release/GYInputPreview.app"
rime_prefix="${GY_RIME_PREFIX:-$root/build/rime-runtime-macos13-arm64}"
rime_shared="$root/../native/runtime/rime/shared"; opencc_data="$rime_prefix/share/opencc"
logo="$root/../native/installer/assets/gy-tray-icon.svg"; identity="${GY_DEVELOPMENT_IDENTITY:-}"
[[ -n "$identity" ]] || identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)"
[[ -n "$identity" ]] || { echo "Apple Development certificate not found." >&2; exit 1; }
[[ ! -e "$release" ]] || { echo "Immutable preview build already exists: $release" >&2; exit 1; }
[[ -f "$rime_prefix/lib/librime.1.dylib" ]] || "$root/scripts/build-rime-runtime.sh"
[[ -f "$rime_prefix/lib/librime.1.dylib" && -f "$rime_shared/gy_pinyin.schema.yaml" && -f "$opencc_data/t2s.json" && -f "$logo" ]] || exit 1
"$root/scripts/verify-preview-input-source-contract.sh" "$plist"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources/Rime"
cp "$plist" "$app/Contents/Info.plist"; ditto "$rime_shared" "$app/Contents/Resources/Rime/shared"; ditto "$opencc_data" "$app/Contents/Resources/Rime/shared/opencc"
iconset="$app/Contents/Resources/GYIcon.iconset"; mkdir "$iconset"
sips -s format png -z 1024 1024 "$logo" --out "$iconset/icon_512x512@2x.png" >/dev/null
for size in 16 32 128 256 512; do sips -z "$size" "$size" "$iconset/icon_512x512@2x.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null; done
for size in 16 32 128 256; do doubled=$((size * 2)); sips -z "$doubled" "$doubled" "$iconset/icon_512x512@2x.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null; done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/GYIcon.icns"
xcrun clang++ -fobjc-arc -mmacosx-version-min=13.0 -I "$rime_prefix/include" -framework Cocoa -framework Carbon -framework InputMethodKit \
  "$root/GYInput/Sources/main.m" "$root/GYInput/Sources/GYInputController.m" "$root/GYInput/Sources/GYCandidateLayout.m" "$root/GYInput/Sources/GYCandidatePanel.m" "$root/GYInput/Sources/GYCandidateQuality.m" \
  "$root/GYInput/Sources/GYActivationEvidence.m" "$root/GYInput/Sources/GYDiagnostics.m" "$root/GYInput/Sources/GYInputMode.m" "$root/GYInput/Sources/GYRimeRuntime.mm" "$root/GYInput/Sources/GYRimeSession.mm" \
  "$rime_prefix/lib/librime.1.dylib" -Wl,-rpath,@executable_path/../Frameworks -o "$app/Contents/MacOS/GYInputPreview"
cp -L "$rime_prefix/lib/librime.1.dylib" "$app/Contents/Frameworks/librime.1.dylib"
workspace="$(mktemp -d)"; GY_RIME_USER_DATA_DIR="$workspace/rime" "$app/Contents/MacOS/GYInputPreview" --self-test
# Self-tests run from a bundle path. Remove that transient Launch Services
# registration so the installed /Library bundle remains the single source of
# truth for this preview bundle ID.
lsregister='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
"$lsregister" -u "$app" || true
mkdir -p "$app/Contents/Resources/Rime/shared/build"
for file in default.yaml luna_pinyin.prism.bin luna_pinyin.reverse.bin luna_pinyin.table.bin gy_pinyin.schema.yaml; do cp "$workspace/rime/build/$file" "$app/Contents/Resources/Rime/shared/build/$file"; done
install_name_tool -id '@rpath/librime.1.dylib' "$app/Contents/Frameworks/librime.1.dylib"
codesign --force --sign "$identity" --timestamp=none "$app/Contents/Frameworks/librime.1.dylib"; codesign --force --sign "$identity" --timestamp=none "$app"
codesign --verify --strict --verbose=2 "$app"; "$root/scripts/verify-bundled-runtime.sh" "$app"
echo "Built immutable macOS preview $version: $app"
