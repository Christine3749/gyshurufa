#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plist="${1:-$root/GYInputPreview/Resources/Info.plist}"
[[ -f "$plist" ]] || { echo "Info.plist not found: $plist" >&2; exit 2; }
/usr/bin/plutil -lint "$plist" >/dev/null
read_key() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null; }
require_equal() {
  local key="$1" expected="$2" actual; actual="$(read_key "$key")"
  [[ "$actual" == "$expected" ]] || { echo "Preview input-source violation: $key must be $expected" >&2; exit 1; }
}
require_equal 'CFBundleIdentifier' 'wang.shurufa.inputmethod.GYInputPreview'
require_equal 'CFBundleExecutable' 'GYInputPreview'
require_equal 'TISInputSourceID' 'wang.shurufa.inputmethod.GYInputPreview'
require_equal 'ComponentInputModeDict:tsInputModeListKey:wang.shurufa.inputmethod.GYInputPreview.pinyin:TISInputSourceID' 'wang.shurufa.inputmethod.GYInputPreview.pinyin'
require_equal 'InputMethodConnectionName' 'wang.shurufa.inputmethod.GYInputPreview.Connection'
require_equal 'InputMethodServerControllerClass' 'GYInputController'
require_equal 'InputMethodServerDelegateClass' 'GYInputController'
require_equal 'GYApplicationSupportFolder' 'GYInputPreview'
echo "Preview input-source contract is valid: $plist"
