#!/bin/bash
set -euo pipefail

target_root="${GY_INPUT_ROOT:-/}"; target_root="${target_root%/}"
app_path="$target_root/Library/Input Methods/GYInput.app"
state_root="$target_root/Library/Application Support/GYInput"
status="$state_root/update-status.plist"
command="${1:-status}"
version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$1/Contents/Info.plist" 2>/dev/null; }
valid_app() { [[ -x "$1/Contents/MacOS/GYInput" ]] && [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist")" == 'wang.shurufa.inputmethod.GYInput' ]]; }
read_status() { /usr/bin/defaults read "$status" "$1" 2>/dev/null || true; }
register_current() {
  local user; user="$(/usr/bin/stat -f '%Su' /dev/console)"
  [[ "$user" == root || "$user" == loginwindow ]] && return 0
  if [[ "$EUID" == 0 ]]; then /usr/bin/sudo -u "$user" "$app_path/Contents/MacOS/GYInput" --register-input-source
  else "$app_path/Contents/MacOS/GYInput" --register-input-source; fi
}
require_root() { [[ "$EUID" == 0 ]] || { echo "Run with sudo: sudo $0 $command" >&2; exit 1; }; }

case "$command" in
  status)
    valid_app "$app_path" || { echo "GYInput.app is not installed at $app_path" >&2; exit 1; }
    printf 'installed=%s\nactivation=%s\nknown-good=%s\nrollback=%s\n' "$(version "$app_path")" "$(read_status activationState)" "$(read_status knownGoodVersion)" "$(read_status rollbackAppPath)"
    ;;
  repair)
    valid_app "$app_path" || { echo 'Installed GYInput.app is invalid.' >&2; exit 1; }; register_current
    echo 'GY registration was rebuilt. Save work and log out/in before judging an active client session.'
    ;;
  mark-known-good)
    require_root; valid_app "$app_path" || { echo 'Installed GYInput.app is invalid.' >&2; exit 1; }
    mkdir -p "$state_root"; /usr/bin/defaults write "$status" knownGoodVersion -string "$(version "$app_path")"
    /usr/bin/defaults write "$status" activationState -string active
    echo "Marked $(version "$app_path") as the rollback baseline."
    ;;
  rollback)
    require_root; valid_app "$app_path" || { echo 'Installed GYInput.app is invalid.' >&2; exit 1; }
    backup="$(read_status rollbackAppPath)"; case "$backup" in "$state_root"/rollback/*) ;; *) echo 'No known-good rollback snapshot is available.' >&2; exit 1;; esac
    valid_app "$backup" || { echo 'Rollback snapshot is invalid.' >&2; exit 1; }
    current="$(version "$app_path")"; restored="$(version "$backup")"; mkdir -p "$state_root/failed"
    stage="$(/usr/bin/mktemp -d "$target_root/Library/Input Methods/.gy-rollback.XXXXXX")"
    /usr/bin/ditto "$backup" "$stage/GYInput.app"; valid_app "$stage/GYInput.app" || exit 1
    stamp="$(/bin/date -u '+%Y%m%dT%H%M%SZ')"; /bin/mv "$app_path" "$state_root/failed/GYInput-$current-$stamp.app"
    /bin/mv "$stage/GYInput.app" "$app_path"; /usr/bin/defaults write "$status" installedVersion -string "$restored"
    /usr/bin/defaults write "$status" activationState -string 'logout-required'; register_current
    echo "Restored $restored. Save work and log out/in before using the restored core."
    ;;
  *) echo 'Usage: GYRecovery.sh {status|repair|mark-known-good|rollback}' >&2; exit 64;;
esac
