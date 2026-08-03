#!/usr/bin/env bash
set -euo pipefail

# Produce a graphical Installer package for invited Apple-Silicon testers.
# It is deliberately separate from package-release.sh: no Developer ID or
# notarization is claimed here, and it must never replace the formal release.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
macos_root="$root/macos"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$macos_root/GYInput/Resources/Info.plist")"
app="$macos_root/.build/DerivedData/Build/Products/Release/GYInput.app"
release_dir="$macos_root/release/beta"
pkg="$release_dir/GYInput-$version-arm64-beta.pkg"

[[ -d "$app" ]] || { echo "Missing release app: $app. Run build-macos.sh first." >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$app"
mkdir -p "$release_dir"
rm -f "$pkg" "$pkg.sha256"

pkgbuild \
  --component "$app" \
  --install-location '/Library/Input Methods' \
  --identifier wang.shurufa.GYInput.beta \
  --version "$version" \
  "$pkg"

pkgutil --check-signature "$pkg"
shasum -a 256 "$pkg" > "$pkg.sha256"
echo "Built unsigned macOS beta installer: $pkg"
