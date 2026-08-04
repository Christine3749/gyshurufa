#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT
cmake -S "$root" -B "$build" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$build" --parallel >/dev/null
ctest --test-dir "$build" --output-on-failure
