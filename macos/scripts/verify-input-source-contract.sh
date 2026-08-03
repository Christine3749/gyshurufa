#!/usr/bin/env bash
# Validates the identity fields that macOS Text Services persists for GY.
# These values are an upgrade ABI. Changing one requires an explicit,
# logout-tested migration rather than an ordinary in-place upgrade.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plist="${1:-$root/GYInput/Resources/Info.plist}"
plistbuddy=/usr/libexec/PlistBuddy

[[ -f "$plist" ]] || { echo "Info.plist not found: $plist" >&2; exit 2; }
/usr/bin/plutil -lint "$plist" >/dev/null

read_key() {
  "$plistbuddy" -c "Print :$1" "$plist" 2>/dev/null
}

require_equal() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(read_key "$key")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'Input-source identity violation: %s must remain %q, got %q in %s\n' \
      "$key" "$expected" "$actual" "$plist" >&2
    exit 1
  fi
}

require_equal 'CFBundleIdentifier' 'wang.shurufa.inputmethod.GYInput'
require_equal 'CFBundleExecutable' 'GYInput'
require_equal 'TISInputSourceID' 'wang.shurufa.inputmethod.GYInput'
require_equal 'ComponentInputModeDict:tsInputModeListKey:wang.shurufa.inputmethod.GYInput.pinyin:TISInputSourceID' 'wang.shurufa.inputmethod.GYInput.pinyin'
require_equal 'InputMethodConnectionName' 'wang.shurufa.inputmethod.GYInput.Connection'
require_equal 'InputMethodServerControllerClass' 'GYInputController'
require_equal 'InputMethodServerDelegateClass' 'GYInputController'

# InputMethodKit requires an input method to create one IMKServer.  Do not try
# to paper over a changed connection name by adding a second legacy server;
# the connection identity must instead remain stable or use an explicit
# migration.  Keep this check close to the plist contract so it cannot drift.
main_source="$root/GYInput/Sources/main.m"
[[ -f "$main_source" ]] || { echo "Missing input-method entry point: $main_source" >&2; exit 2; }
server_count="$(/usr/bin/grep -F -c '[[IMKServer alloc] initWithName:' "$main_source" || true)"
if [[ "$server_count" != 1 ]]; then
  printf 'Input-source identity violation: expected exactly one IMKServer, found %s in %s\n' \
    "$server_count" "$main_source" >&2
  exit 1
fi

# A change of InputMethodKit event protocol needs a dedicated, logout-tested
# migration. Normal releases must retain this text-data route and must not
# reintroduce the legacy direct-event path beside it.
controller_source="$root/GYInput/Sources/GYInputController.m"
[[ -f "$controller_source" ]] || { echo "Missing input controller: $controller_source" >&2; exit 2; }
input_text_route_count="$(/usr/bin/grep -F -c 'inputText:(NSString *)string key:(NSInteger)keyCode modifiers:(NSUInteger)modifiers client:(id)client' "$controller_source" || true)"
legacy_route_count="$(/usr/bin/grep -E -c '^[[:space:]]*-[[:space:]]*\([^)]*\)[[:space:]]*(handleEvent|recognizedEvents)' "$controller_source" || true)"
if [[ "$input_text_route_count" != 1 || "$legacy_route_count" != 0 ]]; then
  printf 'Input event-route violation: require one inputText:key:modifiers:client: implementation and no handleEvent:/recognizedEvents implementation in %s\n' \
    "$controller_source" >&2
  exit 1
fi

echo "Input-source identity contract is valid: $plist"
