#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$root/scripts/verify-input-source-contract.sh"
"$root/scripts/build-core.sh"
"$root/build/GYInput.app/Contents/MacOS/GYInput" --self-test
echo "PASS: offline mode, lexicon, candidate paging, and EN candidate-suppression checks."
