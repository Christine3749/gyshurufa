#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
macos_root="$root/macos"
source_root="$root/native/third_party/librime"
vendor_root="$macos_root/Vendor/rime"
rime_repository="${GY_RIME_REPOSITORY:-https://github.com/rime/librime.git}"
rime_revision="${GY_RIME_REVISION:-1d0df6e40cdcac17a986adc65e4668ae84ae0ada}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "GYInput macOS can only be built on macOS." >&2
  exit 1
fi
if [[ "$(uname -m)" != "arm64" && "${GY_ALLOW_UNIVERSAL:-0}" != "1" ]]; then
  echo "Apple Silicon is required. Set GY_ALLOW_UNIVERSAL=1 only after dual-architecture testing." >&2
  exit 1
fi
command -v make >/dev/null || { echo "Install Xcode command-line tools first." >&2; exit 1; }
command -v git >/dev/null || { echo "Install Git first." >&2; exit 1; }

if [[ "${GY_FORCE_RIME_REBUILD:-0}" != "1" &&
      -f "$vendor_root/include/rime_api.h" &&
      -f "$vendor_root/lib/librime.dylib" ]] &&
   lipo -archs "$vendor_root/lib/librime.dylib" | grep -qw arm64; then
  echo "Using staged arm64 librime: $vendor_root/lib/librime.dylib"
  exit 0
fi

if [[ ! -e "$source_root" ]]; then
  mkdir -p "$(dirname "$source_root")"
  git clone --filter=blob:none --no-checkout "$rime_repository" "$source_root"
  git -C "$source_root" checkout --detach "$rime_revision"
fi
[[ -f "$source_root/src/rime_api.h" ]] || {
  echo "Incomplete librime source: $source_root" >&2
  echo "Remove that directory and rerun this script to restore revision $rime_revision." >&2
  exit 1
}

git -C "$source_root" submodule update --init --recursive
cpu_count="$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
(
  cd "$source_root"
  make deps
  cmake -UGflags_LIBRARY . -Bbuild \
    -DCMAKE_INSTALL_PREFIX="$source_root/dist" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_STATIC=ON \
    -DBUILD_TEST=OFF \
    -DBUILD_MERGED_PLUGINS=OFF \
    -DENABLE_EXTERNAL_PLUGINS=ON
  cmake --build build --parallel "$cpu_count"
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
