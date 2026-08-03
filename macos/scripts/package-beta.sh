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
channel="$(/usr/libexec/PlistBuddy -c 'Print :GYUpdateChannel' "$app/Contents/Info.plist")"
[[ "$channel" == "beta" ]] || { echo "Refusing to package a non-beta update channel as beta: $channel" >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$app"
mkdir -p "$release_dir"
rm -f "$pkg" "$pkg.sha256"

pkgbuild \
  --component "$app" \
  --install-location '/Library/Input Methods' \
  --identifier wang.shurufa.GYInput.beta \
  --version "$version" \
  "$pkg"

signature_report="$(pkgutil --check-signature "$pkg" 2>&1 || true)"
printf '%s\n' "$signature_report"
# pkgutil returns a non-zero status for an intentionally unsigned package.
# Beta packaging must acknowledge that exact state rather than stopping before
# the checksum exists or, worse, accepting an unexpected installer signature.
[[ "$signature_report" == *"Status: no signature"* ]] || {
  echo "Beta package must be unsigned; pkgutil reported an unexpected signature state." >&2
  exit 1
}
shasum -a 256 "$pkg" > "$pkg.sha256"
echo "Built unsigned macOS beta installer: $pkg"
