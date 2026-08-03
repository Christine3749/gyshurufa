#!/usr/bin/env bash
set -euo pipefail

# Read-only diagnostics for a local GY input-method installation.  InputMethodKit
# resolution is sensitive to both filesystem duplicates and stale
# LaunchServices entries, so checking only one of them is not enough.

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_app="$root/.build/DerivedData/Build/Products/Release/GYInput.app"
user_app="$HOME/Library/Input Methods/GYInput.app"
system_app="/Library/Input Methods/GYInput.app"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
expected_app="$build_app"

usage() {
  cat <<'EOF'
Usage: ./scripts/check-local-install-macos.sh [--expected-app PATH]

Checks the local GYInput bundle locations, code signatures, LaunchServices
registrations, and whether the installed executable matches the chosen build.
It does not install, unregister, remove, or modify anything.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-app)
      [[ $# -ge 2 ]] || { echo "--expected-app requires a path." >&2; exit 64; }
      expected_app="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done

[[ "$(uname -s)" == "Darwin" ]] || { echo "GYInput can only be checked on macOS." >&2; exit 1; }

declare -a installed=()
for app in "$user_app" "$system_app"; do
  [[ -d "$app" ]] || continue
  installed+=("$app")
  if ! codesign --verify --deep --strict --verbose=2 "$app"; then
    echo "FAIL: invalid code signature: $app" >&2
    exit 1
  fi
done

if [[ ${#installed[@]} -ne 1 ]]; then
  echo "FAIL: expected exactly one installed GYInput.app; found ${#installed[@]}." >&2
  printf '  %s\n' "${installed[@]:-none}" >&2
  exit 2
fi

installed_app="${installed[0]}"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed_app/Contents/Info.plist")"
[[ "$bundle_id" == "wang.shurufa.inputmethod.GYInput" ]] || {
  echo "FAIL: unexpected bundle identifier: $bundle_id" >&2
  exit 1
}

declare -a registrations=()
while IFS= read -r path; do
  [[ -n "$path" ]] && registrations+=("$path")
done < <("$lsregister" -dump | awk '
  /^path:/{path=$0; sub(/^path:[[:space:]]*/, "", path); sub(/[[:space:]]+\(0x[0-9a-fA-F]+\)$/, "", path)}
  /^identifier: +wang\.shurufa\.inputmethod\.GYInput$/{print path}
')

if [[ ${#registrations[@]} -ne 1 || "${registrations[0]:-}" != "$installed_app" ]]; then
  echo "FAIL: expected one LaunchServices registration for the installed bundle." >&2
  printf '  %s\n' "${registrations[@]:-none}" >&2
  exit 2
fi

if [[ -d "$expected_app" ]]; then
  expected_hash="$(shasum -a 256 "$expected_app/Contents/MacOS/GYInput" | awk '{print $1}')"
  installed_hash="$(shasum -a 256 "$installed_app/Contents/MacOS/GYInput" | awk '{print $1}')"
  if [[ "$expected_hash" != "$installed_hash" ]]; then
    echo "FAIL: installed executable does not match the current build." >&2
    echo "  installed: $installed_hash" >&2
    echo "  expected:  $expected_hash" >&2
    exit 2
  fi
fi

echo "PASS: exactly one signed GYInput bundle and one matching LaunchServices registration."
echo "Installed: $installed_app"
echo "Next: sign out and back in if GY 拼音 is not yet listed in System Settings."
