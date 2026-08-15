#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash macos/scripts/publish-beta-r2.sh <beta-pkg> <macos-beta.json>

Deploys the isolated macOS Beta download route, then uploads one exact unsigned
PKG and its matching R2 metadata. Requires an authenticated Cloudflare Wrangler
session with access to the gy-shurufa-releases bucket.
USAGE
  exit 64
}

PACKAGE_PATH="${1:-}"
MANIFEST_PATH="${2:-}"
[[ -n "$PACKAGE_PATH" && -n "$MANIFEST_PATH" ]] || usage
[[ "$(uname -s)" == "Darwin" ]] || { echo 'This script must run on macOS.' >&2; exit 1; }
[[ -f "$PACKAGE_PATH" && -f "$MANIFEST_PATH" ]] || { echo 'PKG or beta manifest is missing.' >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKER_ROOT="$ROOT/native/release-service"
BUCKET="${GY_R2_BUCKET:-gy-shurufa-releases}"
for command in python3 shasum stat npx curl; do command -v "$command" >/dev/null 2>&1 || { echo "Missing required command: $command" >&2; exit 1; }; done
[[ -f "$WORKER_ROOT/wrangler.jsonc" ]] || { echo "Worker project is missing: $WORKER_ROOT" >&2; exit 1; }

metadata="$(python3 - "$MANIFEST_PATH" "$PACKAGE_PATH" <<'PY'
import hashlib, json, pathlib, re, sys
manifest_path, package_path = map(pathlib.Path, sys.argv[1:])
data = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
version = data.get('version', '')
file_name = data.get('packageFile', '')
sha256 = str(data.get('sha256', '')).lower()
expected_file = f'GYInput-{version}-arm64.pkg'
if data.get('schemaVersion') != 1 or data.get('channel') != 'beta': raise SystemExit('Beta manifest channel/schema is invalid')
if not re.fullmatch(r'\d+\.\d+\.\d+', version): raise SystemExit('Beta version is invalid')
if not isinstance(data.get('build'), int) or data['build'] <= 0: raise SystemExit('Beta build is invalid')
if data.get('architecture') != 'arm64' or file_name != expected_file: raise SystemExit('Beta package identity is invalid')
if package_path.name != file_name: raise SystemExit('PKG filename does not match beta manifest')
actual = hashlib.sha256(package_path.read_bytes()).hexdigest()
if not re.fullmatch(r'[0-9a-f]{64}', sha256) or actual != sha256: raise SystemExit('PKG SHA-256 does not match beta manifest')
if data.get('bytes') != package_path.stat().st_size: raise SystemExit('PKG byte size does not match beta manifest')
print(version)
print(file_name)
PY
)"
VERSION="$(printf '%s\n' "$metadata" | sed -n '1p')"
PACKAGE_FILE="$(printf '%s\n' "$metadata" | sed -n '2p')"
KEY="beta/macos/$VERSION/$PACKAGE_FILE"

cd "$WORKER_ROOT"
npx wrangler deploy
npx wrangler r2 object put "$BUCKET/$KEY" --file "$PACKAGE_PATH" --content-type 'application/vnd.apple.installer+xml'
npx wrangler r2 object put "$BUCKET/beta/macos/latest.json" --file "$MANIFEST_PATH" --content-type 'application/json; charset=utf-8'

FEED_URL='https://www.shurufa.wang/download/macos-beta.json'
DOWNLOAD_URL="https://www.shurufa.wang/download/beta/macos/$VERSION/download"
curl --fail --silent --show-error --retry 3 "$FEED_URL"
printf '\n\nBeta upload verified:\n  %s\n' "$DOWNLOAD_URL"