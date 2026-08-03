#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/build/GYInput.app"
pkg="$root/build/GYInput-core.pkg"
[[ -d "$app" ]] || { echo "Run build-core.sh first." >&2; exit 1; }
"$root/scripts/verify-input-source-contract.sh" "$app/Contents/Info.plist"
[[ ! -e "$pkg" ]] || rm -f "$pkg"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
pkgbuild --component "$app" --install-location '/Library/Input Methods' \
  --scripts "$root/scripts" --identifier wang.shurufa.GYInput.core --version "$version" "$pkg"
signature_report="$(pkgutil --check-signature "$pkg" 2>&1 || true)"
printf '%s\n' "$signature_report"
[[ "$signature_report" == *"Status: no signature"* ]] || { echo "Unexpected package signature state." >&2; exit 1; }
echo "Built minimal GY installer: $pkg"
echo "Release gate: install the package, then run $root/scripts/smoke-test-core.sh"
