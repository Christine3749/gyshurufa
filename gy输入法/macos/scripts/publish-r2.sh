#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
manifest="$root/../release/release.json"
worker_root="$root/native/release-service"
bucket="${GY_R2_BUCKET:-gy-shurufa-releases}"

[[ -f "$manifest" ]] || { echo "Canonical release manifest missing: $manifest" >&2; exit 1; }
readarray -t release < <(python3 - "$manifest" <<'PY'
import json, pathlib, re, sys
d=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
v=d.get('version',''); m=d.get('macos',{})
if not re.fullmatch(r'\d+\.\d+\.\d+',v): raise SystemExit('Invalid canonical version')
if d.get('coreVersion') != v or d.get('hostVersion') != v: raise SystemExit('Release versions do not match')
if m.get('packageFile') != f'GYInput-{v}-arm64.pkg': raise SystemExit('Mac package filename is not canonical')
if not re.fullmatch(r'[A-Fa-f0-9]{64}', str(m.get('sha256',''))): raise SystemExit('Mac SHA-256 missing')
if int(m.get('bytes', 0)) <= 0 or not m.get('signed') or not m.get('notarized') or m.get('state') not in {'notarized','stable'}:
    raise SystemExit('Mac package is not signed/notarized/verified')
print(v); print(m['packageFile']); print(m['sha256'].upper())
PY
)
version="${release[0]}"; file="${release[1]}"; expected_hash="${release[2]}"
pkg="$root/../release/macos/$version/$file"
checksum="$pkg.sha256"
[[ -f "$pkg" && -f "$checksum" ]] || { echo "Missing verified Mac package: $pkg" >&2; exit 1; }
actual_hash="$(shasum -a 256 "$pkg" | awk '{print toupper($1)}')"
[[ "$actual_hash" == "$expected_hash" ]] || { echo "Mac package hash differs from canonical manifest" >&2; exit 1; }
shasum -a 256 -c "$checksum"
pkgutil --check-signature "$pkg"
spctl -a -vv --type install "$pkg"
xcrun stapler validate "$pkg"

cd "$worker_root"
key="releases/$version/macos/$file"
npx wrangler r2 object put "$bucket/$key" --file "$pkg" --content-type application/vnd.apple.installer+xml
npx wrangler r2 object put "$bucket/$key.sha256" --file "$checksum" --content-type 'text/plain; charset=utf-8'

echo "Uploaded immutable Mac package: $key"
echo "latest.json was intentionally NOT changed. The unified publish gate must verify Windows and Mac, then switch it last."
