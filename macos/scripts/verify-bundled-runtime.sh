#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${1:-$root/build/GYInput.app}"
binary="$app/Contents/MacOS/GYInput"
runtime="$app/Contents/Frameworks/librime.1.dylib"

minimum_macos() {
  otool -l "$1" | awk '/LC_BUILD_VERSION/{found=1; next} found && $1 == "minos" {print $2; exit}'
}

[[ -x "$binary" && -f "$runtime" ]] || { echo "Built app or bundled Rime is missing." >&2; exit 1; }
for artifact in "$binary" "$runtime"; do
  minimum="$(minimum_macos "$artifact")"
  [[ "$minimum" == '13.0' ]] || { echo "Unsupported deployment target $minimum: $artifact" >&2; exit 1; }
done
if otool -L "$binary" "$runtime" | grep -Eq '/opt/homebrew|/usr/local/opt'; then
  echo 'Bundled runtime must not depend on Homebrew.' >&2
  exit 1
fi
echo "Bundled runtime is macOS 13 compatible: $app"
