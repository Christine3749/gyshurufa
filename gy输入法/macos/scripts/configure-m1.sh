#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
macos_root="$root/macos"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "GYInput macOS can only be configured on a Mac." >&2
  exit 1
fi

if [[ "$(uname -m)" != "arm64" && "${GY_ALLOW_UNIVERSAL:-0}" != "1" ]]; then
  echo "This first target is Apple Silicon only. Set GY_ALLOW_UNIVERSAL=1 only after testing both architectures." >&2
  exit 1
fi

command -v xcodebuild >/dev/null || { echo "Install Xcode command-line tools first." >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "Install XcodeGen, then rerun this script." >&2; exit 1; }

mkdir -p "$macos_root/GYInput/Resources/rime-data"
rsync -a --delete "$root/native/runtime/rime/shared/" "$macos_root/GYInput/Resources/rime-data/"

cd "$macos_root"
xcodegen generate
echo "Generated $macos_root/GYInputMac.xcodeproj"
echo "Next: ./scripts/build-macos.sh (it stages arm64 librime and produces GYInput.app)."
