#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
macos_root="$root/macos"
source_root="$root/native/third_party/librime"
vendor_root="$macos_root/Vendor/rime"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "GYInput macOS can only be built on macOS." >&2
  exit 1
fi
if [[ "$(uname -m)" != "arm64" && "${GY_ALLOW_UNIVERSAL:-0}" != "1" ]]; then
  echo "Apple Silicon is required. Set GY_ALLOW_UNIVERSAL=1 only after dual-architecture testing." >&2
  exit 1
fi
command -v make >/dev/null || { echo "Install Xcode command-line tools first." >&2; exit 1; }
[[ -f "$source_root/src/rime_api.h" ]] || { echo "Missing bundled librime source: $source_root" >&2; exit 1; }

git -C "$source_root" submodule update --init --recursive
(
  cd "$source_root"
  make deps
  make -j"$(sysctl -n hw.ncpu)"
)

dylib="$(find "$source_root/build" -type f -name 'librime*.dylib' | head -n 1)"
[[ -n "$dylib" && -f "$dylib" ]] || { echo "librime build produced no dylib." >&2; exit 1; }

rm -rf "$vendor_root"
mkdir -p "$vendor_root/include" "$vendor_root/lib"
cp "$source_root/src/rime_api.h" "$vendor_root/include/rime_api.h"
cp "$dylib" "$vendor_root/lib/librime.dylib"
install_name_tool -id '@rpath/librime.dylib' "$vendor_root/lib/librime.dylib"
otool -L "$vendor_root/lib/librime.dylib"
echo "Staged arm64 librime: $vendor_root/lib/librime.dylib"
