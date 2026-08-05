#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
macos_root="$root/macos"
manifest="$root/../release/release.json"
identity="${GY_DEVELOPER_IDENTITY:?Set GY_DEVELOPER_IDENTITY to a Developer ID Application certificate name.}"
installer_identity="${GY_INSTALLER_IDENTITY:?Set GY_INSTALLER_IDENTITY to a Developer ID Installer certificate name.}"
notary_profile="${GY_NOTARY_PROFILE:?Set GY_NOTARY_PROFILE to an xcrun notarytool keychain profile.}"

[[ -f "$manifest" ]] || { echo "Canonical release manifest missing: $manifest" >&2; exit 1; }
readarray -t release < <(python3 - "$manifest" <<'PY'
import json, pathlib, re, sys
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text(encoding='utf-8'))
v = d.get('version', '')
if not re.fullmatch(r'\d+\.\d+\.\d+', v): raise SystemExit('Invalid canonical version')
if d.get('coreVersion') != v or d.get('hostVersion') != v: raise SystemExit('Cross-platform version mismatch')
if d.get('channel') not in {'candidate', 'beta', 'stable'}: raise SystemExit('Invalid release channel')
print(v)
print(d['channel'])
PY
)
version="${release[0]}"
channel="${release[1]}"
release_dir="$root/../release/macos/$version"
pkg="$release_dir/GYInput-$version-arm64.pkg"

# Published artifacts are immutable. A repair must use a new version.
if [[ -e "$release_dir" ]]; then
  echo "Release directory already exists: $release_dir. Refusing to overwrite a versioned Mac release." >&2
  exit 1
fi
mkdir -p "$release_dir"

GY_RELEASE_VERSION="$version" GY_DEVELOPER_IDENTITY="$identity" "$macos_root/scripts/build-macos.sh"
app="$macos_root/.build/DerivedData/Build/Products/Release/GYInput.app"
[[ -d "$app" ]] || { echo "Release app missing: $app" >&2; exit 1; }

pkgbuild \
  --component "$app" \
  --install-location '/Library/Input Methods' \
  --identifier wang.shurufa.GYInput.pkg \
  --version "$version" \
  --scripts "$macos_root/scripts" \
  --sign "$installer_identity" \
  "$pkg"

xcrun notarytool submit "$pkg" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$pkg"
pkgutil --check-signature "$pkg"
spctl -a -vv --type install "$pkg"
shasum -a 256 "$pkg" > "$pkg.sha256"

python3 - "$manifest" "$pkg" "$channel" <<'PY'
import hashlib, json, pathlib, sys
manifest_path = pathlib.Path(sys.argv[1])
package_path = pathlib.Path(sys.argv[2])
channel = sys.argv[3]
raw = package_path.read_bytes()
d = json.loads(manifest_path.read_text(encoding='utf-8'))
v = d['version']
expected = f'GYInput-{v}-arm64.pkg'
if package_path.name != expected: raise SystemExit('Mac package filename does not match canonical release version')
d['macos'] = {
  'packageFile': expected,
  'sha256': hashlib.sha256(raw).hexdigest().upper(),
  'bytes': len(raw),
  'architecture': 'arm64',
  'signed': True,
  'notarized': True,
  'state': 'notarized' if channel != 'stable' else 'stable'
}
manifest_path.write_text(json.dumps(d, indent=2) + '\n', encoding='utf-8')
PY

echo "Notarized immutable Mac package prepared: $pkg"
echo "It is not public yet. Run the unified publish gate from the Windows/release workstation to verify both platforms and switch latest.json."
