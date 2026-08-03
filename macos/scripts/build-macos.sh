#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
macos_root="$root/macos"
derived_data="$macos_root/.build/DerivedData"
configuration="${GY_CONFIGURATION:-Release}"
identity="${GY_DEVELOPER_IDENTITY:-}"
team="${GY_DEVELOPMENT_TEAM:-}"

"$macos_root/scripts/configure-m1.sh"
"$macos_root/scripts/bootstrap-rime-arm64.sh"

rm -rf "$derived_data"
xcodebuild_args=(
  -project "$macos_root/GYInputMac.xcodeproj" \
  -scheme GYInput \
  -configuration "$configuration" \
  -arch arm64 \
  -derivedDataPath "$derived_data"
)
if [[ -n "$team" ]]; then
  xcodebuild_args+=(
    -allowProvisioningUpdates
    DEVELOPMENT_TEAM="$team"
    CODE_SIGN_STYLE=Automatic
    CODE_SIGNING_ALLOWED=YES
  )
else
  xcodebuild_args+=(CODE_SIGNING_ALLOWED=NO)
fi
xcodebuild "${xcodebuild_args[@]}" build

app="$derived_data/Build/Products/$configuration/GYInput.app"
binary="$app/Contents/MacOS/GYInput"
frameworks="$app/Contents/Frameworks"
[[ -x "$binary" ]] || { echo "Expected app executable was not produced: $binary" >&2; exit 1; }

# Rime data and librime are staged by Xcode before its final CodeSign phase.
# Copy Bundle Resources would flatten the directory tree, so a post-compile
# script above uses ditto to preserve rime-data/build exactly.
[[ -f "$app/Contents/Resources/rime-data/build/luna_pinyin.schema.yaml" ]] || {
  echo "Bundled Rime workspace was not staged into GYInput.app." >&2
  exit 1
}

[[ -f "$frameworks/librime.dylib" ]] || { echo "Xcode did not embed librime.dylib." >&2; exit 1; }
linked_rime="$(otool -L "$binary" | awk '/librime/{print $1; exit}')"
[[ -n "$linked_rime" ]] || { echo "GYInput was not linked to librime." >&2; exit 1; }
[[ "$linked_rime" == '@rpath/librime.dylib' ]] || { echo "GYInput must link bundled librime by @rpath, got: $linked_rime" >&2; exit 1; }

plutil -lint "$app/Contents/Info.plist"
if [[ -n "$identity" ]]; then
  codesign --force --timestamp --options runtime --sign "$identity" "$frameworks/librime.dylib"
  codesign --force --timestamp --options runtime --sign "$identity" "$app"
elif [[ -n "$team" ]]; then
  # Xcode's automatic signer owns the Personal Team private key, including
  # cloud-managed development certificates. Do not overwrite its signature.
  :
else
  # Ad-hoc signatures are useful for a local functional test only. The release
  # script refuses to publish until a real Developer ID identity is supplied.
  codesign --force --sign - "$frameworks/librime.dylib"
  codesign --force --sign - "$app"
fi
codesign --verify --strict --verbose=2 "$app"
# Xcode automatically registers an app product from DerivedData. That is
# unsuitable for an InputMethodKit bundle: the installer is the only place
# allowed to register GYInput, otherwise clients can resolve the build product
# instead of /Library or ~/Library/Input Methods.
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$lsregister" -u "$app" >/dev/null 2>&1 || true
echo "Built: $app"
