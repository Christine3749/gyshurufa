#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime="$root/build/rime-runtime-macos13-arm64"
rime_tag='1.17.0'
rime_commit='33e78140250125871856cdc5b42ddc6a5fcd3cd4'
boost_version='1.86.0'
boost_sha256='2575e74ffc3ef1cd0babac2c1ee8bdb5782a0ee672b1912da40e5b4b591ca01f'

need() { command -v "$1" >/dev/null || { echo "Missing build tool: $1" >&2; exit 1; }; }
minimum_macos() { otool -l "$1" | awk '/LC_BUILD_VERSION/{found=1; next} found && $1 == "minos" {print $2; exit}'; }
verify() {
  local library="$1/lib/librime.1.dylib"
  [[ -f "$library" ]] || return 1
  [[ "$(minimum_macos "$library")" == '13.0' ]] || return 1
  ! otool -L "$library" | grep -q '/opt/homebrew'
}

if [[ -d "$runtime" ]]; then
  verify "$runtime" || { echo "Invalid cached Rime runtime: $runtime" >&2; exit 1; }
  echo "Using cached macOS 13 Rime runtime: $runtime"
  exit 0
fi

for tool in cmake curl git otool tar; do need "$tool"; done
work="$(mktemp -d)"
prefix="$work/prefix"
source="$work/librime"
boost_archive="$work/boost_${boost_version//./_}.tar.gz"
boost_source="$work/boost_${boost_version//./_}"
common=(-G 'Unix Makefiles' -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix"
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DCMAKE_OSX_ARCHITECTURES=arm64
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew)

echo "Fetching librime ${rime_tag}…"
git init "$source"
git -C "$source" remote add origin https://github.com/rime/librime.git
git -C "$source" fetch --depth 1 origin "$rime_commit"
git -C "$source" checkout --detach FETCH_HEAD
git -C "$source" submodule update --init --recursive --depth 1
[[ "$(git -C "$source" rev-parse HEAD)" == "$rime_commit" ]] || { echo 'Unexpected librime revision.' >&2; exit 1; }
curl --fail --location --silent --show-error "https://archives.boost.io/release/$boost_version/source/boost_${boost_version//./_}.tar.gz" --output "$boost_archive"
[[ "$(shasum -a 256 "$boost_archive" | awk '{print $1}')" == "$boost_sha256" ]] || { echo 'Boost SHA-256 mismatch.' >&2; exit 1; }
tar -xzf "$boost_archive" -C "$work"
mkdir -p "$prefix/include"
ditto "$boost_source/boost" "$prefix/include/boost"

build() {
  local name="$1" source_path="$2" build_path="$work/build-$1"; shift 2
  cmake -S "$source_path" -B "$build_path" "${common[@]}" "$@"
  cmake --build "$build_path" --parallel 4
  cmake --install "$build_path"
}

build glog "$source/deps/glog" -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DWITH_GFLAGS=OFF
build yaml-cpp "$source/deps/yaml-cpp" -DBUILD_SHARED_LIBS=OFF -DYAML_BUILD_SHARED_LIBS=OFF -DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF -DYAML_CPP_BUILD_CONTRIB=OFF
build leveldb "$source/deps/leveldb" -DBUILD_SHARED_LIBS=OFF -DLEVELDB_BUILD_TESTS=OFF -DLEVELDB_BUILD_BENCHMARKS=OFF
build marisa "$source/deps/marisa-trie" -DBUILD_SHARED_LIBS=OFF -DENABLE_TOOLS=OFF -DBUILD_TESTING=OFF
build opencc "$source/deps/opencc" -DBUILD_SHARED_LIBS=OFF -DENABLE_GTEST=OFF -DENABLE_BENCHMARK=OFF -DBUILD_DOCUMENTATION=OFF -DBUILD_PYTHON=OFF -DUSE_SYSTEM_MARISA=ON -DCMAKE_PREFIX_PATH="$prefix" -DCMAKE_CXX_FLAGS="-I$prefix/include"
build librime "$source" -DCMAKE_PREFIX_PATH="$prefix" -DCMAKE_INCLUDE_PATH="$prefix/include" -DCMAKE_CXX_FLAGS="-I$prefix/include" -DBOOST_ROOT="$prefix" -DBoost_ROOT="$prefix" -DBoost_NO_SYSTEM_PATHS=ON -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC=ON -DBUILD_TEST=OFF -DBUILD_SAMPLE=OFF -DENABLE_EXTERNAL_PLUGINS=OFF -DENABLE_TIMESTAMP=OFF

artifact="$work/runtime"
mkdir -p "$artifact/lib" "$artifact/include" "$artifact/share"
cp -L "$prefix/lib/librime.dylib" "$artifact/lib/librime.1.dylib"
cp "$prefix/include/rime_api.h" "$artifact/include/"
ditto "$prefix/share/opencc" "$artifact/share/opencc"
printf 'librime=%s\nboost=%s\nminimum_macos=13.0\n' "$rime_commit" "$boost_version" > "$artifact/BUILD-INFO"
verify "$artifact" || { echo 'Rime runtime verification failed.' >&2; exit 1; }
mv "$artifact" "$runtime"
echo "Built macOS 13 Rime runtime: $runtime"
