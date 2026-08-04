#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:-expanded}"
case "$mode" in
  collapsed|expanded) ;;
  *) echo 'Usage: preview-candidate-panel.sh {collapsed|expanded}' >&2; exit 64;;
esac
app="$root/build/GYInput.app/Contents/MacOS/GYInput"
[[ -x "$app" ]] || { echo 'Run test-core.sh or build-core.sh first.' >&2; exit 1; }
exec "$app" "--preview-$mode"
