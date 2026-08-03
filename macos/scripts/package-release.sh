#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
macos_root="$root/macos"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$macos_root/GYInput/Resources/Info.plist")"
identity="${GY_DEVELOPER_IDENTITY:?Set GY_DEVELOPER_IDENTITY to a Developer ID Application certificate name.}"
installer_identity="${GY_INSTALLER_IDENTITY:?Set GY_INSTALLER_IDENTITY to a Developer ID Installer certificate name.}"
notary_profile="${GY_NOTARY_PROFILE:?Set GY_NOTARY_PROFILE to an xcrun notarytool keychain profile.}"
release_dir="$macos_root/release/$version"

GY_DEVELOPER_IDENTITY="$identity" "$macos_root/scripts/build-macos.sh"
app="$macos_root/.build/DerivedData/Build/Products/Release/GYInput.app"
[[ -d "$app" ]] || { echo "Release app missing: $app" >&2; exit 1; }

rm -rf "$release_dir"
mkdir -p "$release_dir"
pkg="$release_dir/GYInput-$version-arm64.pkg"
pkgbuild \
  --component "$app" \
  --install-location '/Library/Input Methods' \
  --identifier wang.shurufa.GYInput.pkg \
  --version "$version" \
  --sign "$installer_identity" \
  "$pkg"

xcrun notarytool submit "$pkg" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$pkg"
pkgutil --check-signature "$pkg"
spctl -a -vv --type install "$pkg"
shasum -a 256 "$pkg" > "$pkg.sha256"
echo "Notarized release package: $pkg"
