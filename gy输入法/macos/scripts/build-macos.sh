#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
macos_root="$root/macos"
derived_data="$macos_root/.build/DerivedData"
configuration="${GY_CONFIGURATION:-Release}"
identity="${GY_DEVELOPER_IDENTITY:-}"
release_version="${GY_RELEASE_VERSION:-0.0.0}"
if [[ ! "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "GY_RELEASE_VERSION must use major.minor.patch" >&2; exit 1; fi
build_number="${release_version//./}"

"$macos_root/scripts/bootstrap-rime-arm64.sh"
"$macos_root/scripts/configure-m1.sh"

rm -rf "$derived_data"
xcodebuild \
  -project "$macos_root/GYInputMac.xcodeproj" \
  -scheme GYInput \
  -configuration "$configuration" \
  -arch arm64 \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$release_version" \
  CURRENT_PROJECT_VERSION="$build_number" \
  build

app="$derived_data/Build/Products/$configuration/GYInput.app"
binary="$app/Contents/MacOS/GYInput"
frameworks="$app/Contents/Frameworks"
[[ -x "$binary" ]] || { echo "Expected app executable was not produced: $binary" >&2; exit 1; }

mkdir -p "$frameworks"
cp "$macos_root/Vendor/rime/lib/librime.dylib" "$frameworks/librime.dylib"
linked_rime="$(otool -L "$binary" | awk '/librime/{print $1; exit}')"
[[ -n "$linked_rime" ]] || { echo "GYInput was not linked to librime." >&2; exit 1; }
install_name_tool -change "$linked_rime" '@rpath/librime.dylib' "$binary"

plutil -lint "$app/Contents/Info.plist"
if [[ -n "$identity" ]]; then
  codesign --force --timestamp --options runtime --sign "$identity" "$frameworks/librime.dylib"
  codesign --force --timestamp --options runtime --sign "$identity" "$app"
else
  # Ad-hoc signatures are useful for a local functional test only. The release
  # script refuses to publish until a real Developer ID identity is supplied.
  codesign --force --sign - "$frameworks/librime.dylib"
  codesign --force --sign - "$app"
fi
codesign --verify --strict --verbose=2 "$app"
echo "Built: $app"
