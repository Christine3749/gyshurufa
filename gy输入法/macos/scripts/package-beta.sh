#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash macos/scripts/package-beta.sh <GYInput.app> [output-directory]

Creates an unsigned, self-test-only PKG and its R2 beta metadata manifest.
USAGE
  exit 64
}

APP_PATH="${1:-}"
OUTPUT_DIRECTORY="${2:-}"
[[ -n "$APP_PATH" ]] || usage
[[ "$(uname -s)" == "Darwin" ]] || { echo 'This script must run on macOS.' >&2; exit 1; }
[[ "$(uname -m)" == "arm64" ]] || { echo 'This beta package is restricted to Apple Silicon Macs.' >&2; exit 1; }
[[ -d "$APP_PATH/Contents" && -f "$APP_PATH/Contents/Info.plist" ]] || { echo "Not an app bundle: $APP_PATH" >&2; exit 1; }

for command in pkgbuild shasum stat /usr/libexec/PlistBuddy; do
  command -v "$command" >/dev/null 2>&1 || { echo "Missing required command: $command" >&2; exit 1; }
done

PLIST="$APP_PATH/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || { echo "Unexpected CFBundleShortVersionString: $VERSION" >&2; exit 1; }
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || { echo "Unexpected CFBundleVersion: $BUILD" >&2; exit 1; }

if [[ -z "$OUTPUT_DIRECTORY" ]]; then
  OUTPUT_DIRECTORY="$(dirname "$APP_PATH")/beta-release"
fi
mkdir -p "$OUTPUT_DIRECTORY"
PACKAGE_FILE="GYInput-${VERSION}-arm64.pkg"
PACKAGE_PATH="$OUTPUT_DIRECTORY/$PACKAGE_FILE"
MANIFEST_PATH="$OUTPUT_DIRECTORY/macos-beta.json"

# Deliberately unsigned: this script is for self-test Beta distribution only.
pkgbuild --identifier 'wang.shurufa.inputmethod.GYInput.beta' --version "$VERSION" --install-location '/Library/Input Methods' --component "$APP_PATH" "$PACKAGE_PATH"

SHA256="$(shasum -a 256 "$PACKAGE_PATH" | awk '{print $1}')"
BYTES="$(stat -f '%z' "$PACKAGE_PATH")"
printf '{"schemaVersion":1,"channel":"beta","version":"%s","build":%s,"architecture":"arm64","packageFile":"%s","sha256":"%s","bytes":%s}\n' "$VERSION" "$BUILD" "$PACKAGE_FILE" "$SHA256" "$BYTES" > "$MANIFEST_PATH"

printf '\nBeta package created:\n  %s\n\nR2 beta manifest created:\n  %s\n\nNext, run publish-beta-r2.sh with these two paths.\n' "$PACKAGE_PATH" "$MANIFEST_PATH"
printf '\nAfter downloading the unsigned test package on your own Mac:\n  xattr -dr com.apple.quarantine "%s"\n  sudo installer -pkg "%s" -target /\n' "$PACKAGE_PATH" "$PACKAGE_PATH"