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
archive="${1:-$site_root/public/download/GYInput-$version-arm64-beta.zip}"
name="$(basename "$archive")"
key="releases/macos/beta/$version/$name"
manifest="$(mktemp)"

cleanup() { rm -f "$manifest"; }
trap cleanup EXIT

[[ -f "$archive" ]] || { echo "Missing beta archive: $archive" >&2; exit 1; }
command -v npx >/dev/null || { echo "Node.js/npx is required to upload through Wrangler." >&2; exit 1; }

sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
node --input-type=commonjs - "$manifest" "$version" "$key" "$name" "$sha256" <<'NODE'
const fs = require('node:fs');
const [output, version, key, name, sha256] = process.argv.slice(2);
fs.writeFileSync(output, JSON.stringify({
  version: `${version} 内测版`,
  releaseNotes: 'Apple Silicon 内测包；未使用 Developer ID 公证。',
  artifacts: {
    '/macos-beta.zip': { key, name, type: 'application/zip', sha256 },
  },
}, null, 2) + '\n');
NODE

cd "$worker_root"
npx wrangler r2 object put "gy-shurufa-releases/$key" --file "$archive" --content-type application/zip
npx wrangler r2 object put 'gy-shurufa-releases/releases/macos/beta/latest.json' --file "$manifest" --content-type 'application/json; charset=utf-8'
npx wrangler deploy

echo "Published macOS beta through R2: https://www.shurufa.wang/download/$name"
echo "SHA-256: $sha256"
