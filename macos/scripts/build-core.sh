#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/build/GYInput.app"
manifest="$root/../release/release.json"
rime_prefix="${GY_RIME_PREFIX:-$(brew --prefix librime)}"
rime_shared="$root/../native/runtime/rime/shared"
opencc_data="$(brew --prefix opencc)/share/opencc"
logo="$root/../native/installer/assets/gy-tray-icon.svg"
identity="${GY_DEVELOPMENT_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)"
fi
[[ -n "$identity" ]] || { echo "Apple Development certificate not found." >&2; exit 1; }
[[ -f "$manifest" ]] || { echo "Release manifest not found: $manifest" >&2; exit 1; }
[[ -f "$rime_prefix/lib/librime.dylib" ]] || { echo "Apple Silicon librime is required." >&2; exit 1; }
[[ -f "$rime_shared/gy_pinyin.schema.yaml" ]] || { echo "Shared GY Rime data is missing." >&2; exit 1; }
[[ -f "$opencc_data/t2s.json" ]] || { echo "OpenCC conversion data is required." >&2; exit 1; }
[[ -f "$logo" ]] || { echo "Shared GY logo is missing." >&2; exit 1; }
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
"$root/scripts/verify-input-source-contract.sh" "$app/Contents/Info.plist"
xcrun clang++ -fobjc-arc -mmacosx-version-min=13.0 -I "$root/../native/runtime/rime/include" \
  -framework Cocoa -framework Carbon -framework InputMethodKit \
  "$root/GYInput/Sources/main.m" "$root/GYInput/Sources/GYInputController.m" \
  "$root/GYInput/Sources/GYDiagnostics.m" "$root/GYInput/Sources/GYInputMode.m" \
  "$root/GYInput/Sources/GYRimeRuntime.mm" "$root/GYInput/Sources/GYRimeSession.mm" \
  -L "$rime_prefix/lib" -lrime -Wl,-rpath,@executable_path/../Frameworks -o "$app/Contents/MacOS/GYInput"

cp -L "$rime_prefix/lib/librime.dylib" "$app/Contents/Frameworks/librime.1.dylib"
libraries=(
  "$(brew --prefix glog)/lib/libglog.2.dylib"
  "$(brew --prefix yaml-cpp)/lib/libyaml-cpp.0.9.dylib"
  "$(brew --prefix gflags)/lib/libgflags.2.3.dylib"
  "$(brew --prefix leveldb)/lib/libleveldb.1.dylib"
  "$(brew --prefix marisa)/lib/libmarisa.0.dylib"
  "$(brew --prefix opencc)/lib/libopencc.1.4.dylib"
  "$(brew --prefix snappy)/lib/libsnappy.1.dylib"
)
for library in "${libraries[@]}"; do cp -L "$library" "$app/Contents/Frameworks/"; done
for library in "$app/Contents/Frameworks"/*.dylib "$app/Contents/MacOS/GYInput"; do
  install_name_tool -id "@rpath/$(basename "$library")" "$library" 2>/dev/null || true
  while read -r dependency; do
    target="$app/Contents/Frameworks/$(basename "$dependency")"
    [[ -f "$target" ]] && install_name_tool -change "$dependency" "@rpath/$(basename "$dependency")" "$library"
  done < <(otool -L "$library" | awk 'NR > 1 {print $1}')
done
for library in "$app/Contents/Frameworks"/*.dylib; do codesign --force --sign "$identity" --timestamp=none "$library"; done
codesign --force --sign "$identity" --timestamp=none "$app"
plutil -lint "$app/Contents/Info.plist"
codesign --verify --strict --verbose=2 "$app"
echo "Built GY macOS input core $release_version: $app"
