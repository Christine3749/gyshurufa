#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plist="$root/GYInputPreview/Resources/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
app="$root/build/preview-$version/GYInputPreview.app"; pkg="$root/build/GYInputPreview-$version-arm64.pkg"
[[ -d "$app" ]] || { echo "Run build-preview.sh first." >&2; exit 1; }
[[ ! -e "$pkg" ]] || { echo "Immutable preview package already exists: $pkg" >&2; exit 1; }
"$root/scripts/verify-preview-input-source-contract.sh" "$app/Contents/Info.plist"; "$root/scripts/verify-bundled-runtime.sh" "$app"
pkgbuild --component "$app" --install-location '/Library/Input Methods' --scripts "$root/preview-scripts" --identifier wang.shurufa.GYInputPreview.core --version "$version" "$pkg"
signature="$(pkgutil --check-signature "$pkg" 2>&1 || true)"
printf '%s\n' "$signature"
[[ "$signature" == *"Status: no signature"* ]] || { echo "Unexpected package signature state." >&2; exit 1; }
echo "Built Mac preview installer: $pkg"
