#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$root/../shared/session/test-session-guard.sh"
"$root/scripts/verify-input-source-contract.sh"
"$root/scripts/build-core.sh"
workspace="$(mktemp -d)"
mkdir -p "$workspace/rime/build"
printf 'schema:\n  page_size: 5\n' > "$workspace/rime/build/gy_pinyin.schema.yaml"
GY_RIME_USER_DATA_DIR="$workspace/rime" "$root/build/GYInput.app/Contents/MacOS/GYInput" --self-test
grep -q 'page_size: 25' "$workspace/rime/build/gy_pinyin.schema.yaml"
"$root/scripts/test-upgrade-safety.sh"
echo "PASS: shared Rime schema, Simplified/Traditional candidates, and bundled runtime checks."
