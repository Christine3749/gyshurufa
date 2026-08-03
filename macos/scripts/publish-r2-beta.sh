#!/usr/bin/env bash
set -euo pipefail

# Upload the transparent Apple-Silicon beta only.  This deliberately does not
# write the notarized /latest-macos.pkg feed, which is reserved for Developer
# ID signed and notarized releases.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
macos_root="$root/macos"
site_root="$root/../gy输入法---官方网站"
worker_root="$site_root/download-worker"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$macos_root/GYInput/Resources/Info.plist")"
archive="${1:-$macos_root/release/beta/GYInput-$version-arm64-beta.pkg}"
name="$(basename "$archive")"
key="releases/macos/beta/$version/$name"
manifest="$(mktemp)"

cleanup() { rm -f "$manifest"; }
trap cleanup EXIT

[[ -f "$archive" ]] || { echo "Missing beta archive: $archive" >&2; exit 1; }
command -v npx >/dev/null || { echo "Node.js/npx is required to upload through Wrangler." >&2; exit 1; }

case "$name" in
  *.pkg) content_type='application/vnd.apple.installer+xml' ;;
  *.zip) content_type='application/zip' ;;
  *) echo "Beta archive must be a .pkg or .zip file: $name" >&2; exit 1 ;;
esac

sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
node --input-type=commonjs - "$manifest" "$version" "$key" "$name" "$sha256" "$content_type" <<'NODE'
const fs = require('node:fs');
const [output, version, key, name, sha256, type] = process.argv.slice(2);
fs.writeFileSync(output, JSON.stringify({
  version: `${version} 内测版`,
  releaseNotes: 'Apple Silicon 内测包；未使用 Developer ID 公证。',
  artifacts: {
    '/macos-beta': { key, name, type, sha256 },
  },
}, null, 2) + '\n');
NODE

cd "$worker_root"
npx wrangler r2 object put "gy-shurufa-releases/$key" --file "$archive" --content-type "$content_type" --remote
npx wrangler r2 object put 'gy-shurufa-releases/releases/macos/beta/latest.json' --file "$manifest" --content-type 'application/json; charset=utf-8' --remote
npx wrangler deploy

echo "Published macOS beta through R2: https://www.shurufa.wang/download/$name"
echo "SHA-256: $sha256"
