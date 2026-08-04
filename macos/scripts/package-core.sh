#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/build/GYInput.app"
[[ -d "$app" ]] || { echo "Run build-core.sh first." >&2; exit 1; }
"$root/scripts/verify-input-source-contract.sh" "$app/Contents/Info.plist"
runtime="$app/Contents/Frameworks/librime.1.dylib"
minimum="$(otool -l "$runtime" | awk '/LC_BUILD_VERSION/{found=1; next} found && $1 == "minos" {print $2; exit}')"
major="${minimum%%.*}"
if [[ -n "$major" && "$major" -gt 13 && "${GY_ALLOW_DEVELOPMENT_RUNTIME:-}" != "1" ]]; then
  echo "Refusing release package: bundled librime requires macOS $minimum (project target: 13.0)." >&2
  echo "Build Rime for macOS 13.0; only local testing may use GY_ALLOW_DEVELOPMENT_RUNTIME=1." >&2
  exit 1
fi
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
pkg="$root/build/GYInput-${version}-arm64.pkg"
[[ ! -e "$pkg" ]] || rm -f "$pkg"
pkgbuild --component "$app" --install-location '/Library/Input Methods' \
  --scripts "$root/scripts" --identifier wang.shurufa.GYInput.core --version "$version" "$pkg"
signature_report="$(pkgutil --check-signature "$pkg" 2>&1 || true)"
printf '%s\n' "$signature_report"
[[ "$signature_report" == *"Status: no signature"* ]] || { echo "Unexpected package signature state." >&2; exit 1; }
echo "Built GY macOS installer: $pkg"
[[ "${GY_ALLOW_DEVELOPMENT_RUNTIME:-}" != "1" ]] || echo "DEVELOPER-ONLY: Rime runtime requires macOS $minimum. Do not distribute."
echo "Release gate: install the package, then run $root/scripts/smoke-test-core.sh"
