#!/usr/bin/env bash
set -euo pipefail

# Install one—and only one—development GY input-method bundle.  macOS text
# clients can resolve duplicate bundles with the same identifier differently,
# so a user copy plus a system copy is not a supported test configuration.

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/.build/DerivedData/Build/Products/Release/GYInput.app"
user_target="$HOME/Library/Input Methods/GYInput.app"
system_target="/Library/Input Methods/GYInput.app"
mode="user"
replace_user_copy=0

usage() {
  cat <<'EOF'
Usage: ./scripts/install-local-macos.sh [--user | --system] [--replace-user-copy] [--app PATH]

  --user                Install only in ~/Library/Input Methods (default).
  --system              Install only in /Library/Input Methods (requires sudo).
  --replace-user-copy   With --system, move an existing user-level GYInput.app
                        to Trash before installing. This prevents duplicate IDs.
  --app PATH            Use an already-built GYInput.app instead of the default.

For a local M1 test, choose --user. For a machine-wide test, choose --system.
Never keep both locations populated with GYInput.app at the same time.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) mode="user" ;;
    --system) mode="system" ;;
    --replace-user-copy) replace_user_copy=1 ;;
    --app)
      [[ $# -ge 2 ]] || { echo "--app requires a path." >&2; exit 64; }
      app="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done

[[ "$(uname -s)" == "Darwin" ]] || { echo "GYInput can only be installed on macOS." >&2; exit 1; }
[[ -d "$app" ]] || { echo "GYInput.app not found: $app" >&2; exit 1; }
[[ -x "$app/Contents/MacOS/GYInput" ]] || { echo "The input-method bundle is incomplete: $app" >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$app"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
[[ "$bundle_id" == "wang.shurufa.inputmethod.GYInput" ]] || {
  echo "Refusing unexpected input-method identifier: $bundle_id" >&2
  exit 1
}

if [[ "$mode" == "system" ]]; then
  # Validate the administrator credential before moving a user copy to Trash.
  # A cancelled password prompt must leave the current working input method
  # untouched and recoverable in its original location.
  sudo -v
fi

if [[ "$mode" == "user" && -d "$system_target" ]]; then
  cat >&2 <<EOF
Refusing to install a second GYInput bundle.

Existing system copy: $system_target
Choose one location only. To update the system copy and archive the user copy,
run: ./scripts/install-local-macos.sh --system --replace-user-copy
EOF
  exit 2
fi

if [[ "$mode" == "system" && -d "$user_target" ]]; then
  if [[ "$replace_user_copy" != "1" ]]; then
    cat >&2 <<EOF
Refusing to keep a user and a system GYInput bundle at the same time.

Existing user copy: $user_target
If the system location is intentional, rerun with --replace-user-copy. The
existing user copy will be moved to Trash, not deleted permanently.
EOF
    exit 2
  fi
fi

if [[ "$mode" == "user" ]]; then
  mkdir -p "$(dirname "$user_target")"
  ditto "$app" "$user_target"
  target="$user_target"
else
  # Stage and validate the replacement before touching either live bundle.
  # In particular, a cancelled disk operation must not leave the user with no
  # registered input method after their user-level copy has been archived.
  staging_target="/Library/Input Methods/.GYInput.app.stage.$$"
  backup_target="/Library/Input Methods/.GYInput.app.backup.$(date +%Y%m%d-%H%M%S)"
  sudo rm -rf "$staging_target"
  sudo ditto "$app" "$staging_target"
  sudo codesign --verify --deep --strict --verbose=2 "$staging_target"

  if [[ -d "$system_target" ]]; then
    sudo mv "$system_target" "$backup_target"
  fi
  if ! sudo mv "$staging_target" "$system_target" ||
      ! sudo codesign --verify --deep --strict --verbose=2 "$system_target"; then
    sudo rm -rf "$system_target"
    [[ -d "$backup_target" ]] && sudo mv "$backup_target" "$system_target"
    echo "The system copy was restored because the replacement could not be validated." >&2
    exit 1
  fi

  # Only now is it safe to remove the duplicate user copy. This is
  # recoverable: it goes to Trash, not a privileged deletion.
  if [[ -d "$user_target" ]]; then
    trash_target="$HOME/.Trash/GYInput.app.$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$HOME/.Trash"
    mv "$user_target" "$trash_target"
    echo "Moved conflicting user copy to Trash: $trash_target"
  fi
  [[ -d "$backup_target" ]] && sudo rm -rf "$backup_target"
  target="$system_target"
fi

lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
# Xcode registers the DerivedData product while building.  Keep that temporary
# registration (and a just-archived user copy) out of the resolver, otherwise
# Safari and AppKit can bind different controllers despite a single bundle on
# disk.  Re-register only the installed target below.
"$lsregister" -u "$app" >/dev/null 2>&1 || true
"$lsregister" -u "$user_target" >/dev/null 2>&1 || true
if [[ -n "${trash_target:-}" ]]; then
  "$lsregister" -u "$trash_target" >/dev/null 2>&1 || true
fi
# A previously interrupted update can leave a recoverable bundle in Trash.
# Do not let it remain as a second input-source registration.
for stale_trash_target in "$HOME"/.Trash/GYInput.app.*; do
  [[ -e "$stale_trash_target" ]] || continue
  "$lsregister" -u "$stale_trash_target" >/dev/null 2>&1 || true
done
"$lsregister" -u "$system_target" >/dev/null 2>&1 || true
"$lsregister" -f -R -trusted "$target"
codesign --verify --deep --strict --verbose=2 "$target"

echo "Installed exactly one GYInput bundle: $target"
echo "Now open System Settings → Keyboard → Input Sources and select GY输入法."
