#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${1:-$root/build/GYInput.app}"
version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist"; }
[[ -x "$app/Contents/MacOS/GYInput" ]] || { echo "App is missing: $app" >&2; exit 1; }
! /usr/bin/grep -Eq 'pkill|/usr/bin/open' "$root/scripts/postinstall" || { echo 'Postinstall must not restart an active IMK core.' >&2; exit 1; }

sandbox="$(mktemp -d)"; trap 'rm -rf "$sandbox"' EXIT
input_root="$sandbox/Library/Input Methods"
state_root="$sandbox/Library/Application Support/GYInput"
user_home="$sandbox/user"
baseline="$user_home/Library/Application Support/GYInput/physical-baseline.plist"
mkdir -p "$input_root" "$state_root" "$(dirname "$baseline")"
/usr/bin/ditto "$app" "$input_root/GYInput.app"
/usr/bin/defaults write "$baseline" version -string "$(version "$app")"
GY_INPUT_BASELINE_HOME="$user_home" "$root/scripts/preinstall" ignored '/Library/Input Methods' "$sandbox"
backup="$state_root/rollback/GYInput-$(version "$app").app"
[[ -x "$backup/Contents/MacOS/GYInput" ]] || { echo 'Known-good app was not snapshotted.' >&2; exit 1; }
"$root/scripts/postinstall" ignored '/Library/Input Methods' "$sandbox" >/dev/null
[[ "$(/usr/bin/stat -f '%Lp' "$state_root/update-status.plist")" == 644 ]] || { echo 'Upgrade status must be user-readable.' >&2; exit 1; }
status="$(GY_INPUT_ROOT="$sandbox" "$root/scripts/GYRecovery.sh" status)"
[[ "$status" == *'activation=logout-required'* && "$status" == *"known-good=$(version "$app")"* && "$status" == *"rollback=$backup"* ]] || { echo 'Upgrade status is incomplete.' >&2; exit 1; }
echo 'PASS: upgrade preserves the known-good GY core and requires logout activation.'
