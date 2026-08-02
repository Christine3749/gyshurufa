#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app="${1:-$root/macos/.build/DerivedData/Build/Products/Release/GYInput.app}"
release_mode="${GY_RELEASE_VERIFY:-0}"

[[ -d "$app" ]] || { echo "GYInput.app not found: $app" >&2; exit 1; }
binary="$app/Contents/MacOS/GYInput"
rime="$app/Contents/Frameworks/librime.dylib"
data="$app/Contents/Resources/rime-data/build"
[[ -x "$binary" && -f "$rime" && -d "$data" ]] || { echo "App bundle is incomplete." >&2; exit 1; }

plutil -lint "$app/Contents/Info.plist"
codesign --verify --strict --verbose=2 "$app"
file "$binary" | grep -q 'arm64' || { echo "GYInput binary is not arm64." >&2; exit 1; }
file "$rime" | grep -q 'arm64' || { echo "Bundled librime is not arm64." >&2; exit 1; }
otool -L "$binary" | grep -q '@rpath/librime.dylib' || { echo "GYInput does not use its bundled librime." >&2; exit 1; }
if otool -L "$binary" "$rime" | grep -E '/opt/homebrew|/usr/local'; then
  echo "Release bundle links to a developer-machine dependency." >&2
  exit 1
fi
for file in default.yaml luna_pinyin.prism.bin luna_pinyin.reverse.bin luna_pinyin.schema.yaml luna_pinyin.table.bin; do
  [[ -f "$data/$file" ]] || { echo "Rime workspace missing $file." >&2; exit 1; }
done

if [[ "$release_mode" == "1" ]]; then
  codesign -dvv "$app" 2>&1 | grep -q 'Developer ID Application' || { echo "Release verification requires a Developer ID application signature." >&2; exit 1; }
  spctl -a -vv --type execute "$app"
fi

echo "PASS: arm64 GYInput bundle, embedded librime, and precompiled Rime workspace are valid."
