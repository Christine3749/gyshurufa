#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
macos_root="$root/macos"
source_root="$root/native/third_party/librime"
vendor_root="$macos_root/Vendor/rime"
boost_root="$source_root/deps/boost-1.89.0"

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

# librime's macOS build needs Boost headers. Keep the source-local Boost copy
# so the produced input method never links to a Homebrew Boost installation.
if [[ ! -f "$boost_root/boost/version.hpp" ]]; then
  (
    cd "$source_root"
    bash ./install-boost.sh
  )
fi
[[ -f "$boost_root/boost/version.hpp" ]] || { echo "Boost headers are missing: $boost_root" >&2; exit 1; }

# The workspace may have been opened on Windows before reaching this M1 build.
# CMake embeds absolute source paths in CMakeCache.txt and refuses to reuse a
# cache from a different path/OS. Remove only those generated build folders;
# never touch librime source, dictionaries, or installed user data.
clean_stale_cmake_cache() {
  local build_dir="$1"
  local source_dir="$2"
  local cache="$build_dir/CMakeCache.txt"
  [[ -f "$cache" ]] || return 0
  local expected="CMAKE_HOME_DIRECTORY:INTERNAL=$source_dir"
  if ! grep -Fqx "$expected" "$cache"; then
    echo "Removing stale CMake cache: $build_dir"
    rm -rf "$build_dir"
  fi
}

clean_stale_cmake_cache "$source_root/build" "$source_root"
for dependency in glog googletest leveldb marisa-trie opencc yaml-cpp; do
  clean_stale_cmake_cache "$source_root/deps/$dependency/build" "$source_root/deps/$dependency"
done

git -C "$source_root" submodule update --init --recursive
(
  cd "$source_root"
  # Pass this as a make variable (rather than only an environment variable),
  # so an inherited BUILD_UNIVERSAL setting cannot silently create a fat dylib.
  make CMAKE_OSX_ARCHITECTURES=arm64 deps
  # librime's Makefile declares CMAKE_BOOST_OPTIONS but does not pass it to
  # CMake. Configure explicitly so the bundled Boost headers are always used.
  cmake -S . -B build \
    -DCMAKE_INSTALL_PREFIX="$source_root/dist" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_MERGED_PLUGINS=OFF \
    -DENABLE_EXTERNAL_PLUGINS=ON \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DBoost_NO_BOOST_CMAKE=TRUE \
    -DBOOST_ROOT="$boost_root" \
    -DCMAKE_POLICY_DEFAULT_CMP0167=OLD
  cmake --build build --parallel "$(sysctl -n hw.ncpu)"
)

dylib="$(find "$source_root/build" -type f -name 'librime*.dylib' | head -n 1)"
[[ -n "$dylib" && -f "$dylib" ]] || { echo "librime build produced no dylib." >&2; exit 1; }
lipo -archs "$dylib" | grep -qx 'arm64' || { echo "librime must be arm64-only, got: $(lipo -archs "$dylib")" >&2; exit 1; }

rm -rf "$vendor_root"
mkdir -p "$vendor_root/include" "$vendor_root/lib"
cp "$source_root/src/rime_api.h" "$vendor_root/include/rime_api.h"
cp "$dylib" "$vendor_root/lib/librime.dylib"
install_name_tool -id '@rpath/librime.dylib' "$vendor_root/lib/librime.dylib"
otool -L "$vendor_root/lib/librime.dylib"
echo "Staged arm64 librime: $vendor_root/lib/librime.dylib"
