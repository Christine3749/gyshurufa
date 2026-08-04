#!/usr/bin/env bash
# Interactive release gate.  It deliberately requires a physical keyboard:
# synthetic accessibility input does not prove that Text Services routes keys
# to an InputMethodKit controller.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${1:-/Library/Input Methods/GYInput.app}"
trace_file='/tmp/GYInput-core.trace'
source_id='wang.shurufa.inputmethod.GYInput.pinyin'

if [[ ! -d "$app" && -d "$root/build/GYInput.app" ]]; then
  app="$root/build/GYInput.app"
fi
[[ -x "$app/Contents/MacOS/GYInput" ]] || { echo "GYInput.app not found: $app" >&2; exit 2; }
"$root/scripts/verify-input-source-contract.sh" "$app/Contents/Info.plist"

start_bytes=0
[[ -f "$trace_file" ]] && start_bytes="$(/usr/bin/wc -c < "$trace_file" | /usr/bin/tr -d ' ')"

echo "Selecting $source_id for this logged-in user…"
/usr/bin/xcrun swift - "$source_id" <<'SWIFT'
import Carbon
import Foundation

let sourceID = CommandLine.arguments[1] as CFString
let properties = [kTISPropertyInputSourceID: sourceID] as CFDictionary
let sources = TISCreateInputSourceList(properties, false).takeRetainedValue() as! [TISInputSource]
guard let source = sources.first else {
  fputs("GY input source is not registered. Install the package first.\n", stderr)
  exit(2)
}
guard TISSelectInputSource(source) == noErr else {
  fputs("Could not select GY input source.\n", stderr)
  exit(3)
}
let selected = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
guard let rawID = TISGetInputSourceProperty(selected, kTISPropertyInputSourceID) else {
  fputs("Could not read selected input source.\n", stderr)
  exit(4)
}
let selectedID = Unmanaged<CFString>.fromOpaque(rawID).takeUnretainedValue() as String
guard selectedID == sourceID as String else {
  fputs("GY was not selected; current source is \(selectedID).\n", stderr)
  exit(5)
}
print("Selected \(selectedID)")
SWIFT

/usr/bin/open -a TextEdit
printf '\nManual release gate (synthetic input is invalid):\n'
printf '1. Click the TextEdit document.\n'
printf '2. Type nihao with the physical keyboard, then press Space.\n'
printf '3. Confirm that TextEdit committed “你好”, then return here and press Return.\n'
read -r _

if [[ -f "$trace_file" ]]; then
  new_trace="$(/usr/bin/tail -c +"$((start_bytes + 1))" "$trace_file" 2>/dev/null || true)"
else
  new_trace=''
fi
event_count="$(printf '%s\n' "$new_trace" | /usr/bin/grep -c '^text-event$' || true)"
printf '\nNew controller trace:\n%s\n' "${new_trace:-<none>}"

if (( event_count < 6 )); then
  printf 'FAIL: expected at least 6 text-event records for nihao + Space; found %s.\n' "$event_count" >&2
  printf 'Do not release. Diagnose the input-source registration before changing key-handling code.\n' >&2
  exit 1
fi

printf 'PASS: physical-keyboard smoke test observed %s text-event records.\n' "$event_count"
user_home="$(/usr/bin/dscl . -read "/Users/$(/usr/bin/id -un)" NFSHomeDirectory | /usr/bin/awk '{print $2}')"
baseline="$user_home/Library/Application Support/GYInput/physical-baseline.plist"
route="$user_home/Library/Application Support/GYInput/core-route.plist"
mkdir -p "$(dirname "$baseline")"
/usr/bin/defaults write "$baseline" version -string "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
/usr/bin/defaults write "$baseline" verifiedAt -string "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
/usr/bin/defaults write "$route" version -string "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
/usr/bin/defaults write "$route" verifiedAt -string "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "Saved physical-keyboard baseline: $baseline"
printf 'Mark this version as a rollback baseline: sudo %q mark-known-good\n' "$app/Contents/Resources/GYRecovery.sh"
