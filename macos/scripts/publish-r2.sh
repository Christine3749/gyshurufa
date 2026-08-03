#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
macos_root="$root/macos"
worker_root="$root/../gy输入法---官方网站/download-worker"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$macos_root/GYInput/Resources/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$macos_root/GYInput/Resources/Info.plist")"
release_dir="$macos_root/release/$version"
pkg="$release_dir/GYInput-$version-arm64.pkg"
checksum="$pkg.sha256"
key="releases/$version/$(basename "$pkg")"
manifest="$release_dir/latest-macos.json"

[[ -f "$pkg" && -f "$checksum" ]] || { echo "Missing notarized package or SHA-256 file in $release_dir" >&2; exit 1; }
command -v npx >/dev/null || { echo "Node.js/npx is required to upload through Wrangler." >&2; exit 1; }
command -v pkgutil >/dev/null || { echo "Run this only on macOS." >&2; exit 1; }
shasum -a 256 -c "$checksum"
pkgutil --check-signature "$pkg"
spctl -a -vv --type install "$pkg"
xcrun stapler validate "$pkg"

# Keep macOS update metadata separate from the Windows latest.json feed. The
# input method checks this signed-release-only feed but never silently writes
# /Library/Input Methods; macOS still presents administrator authorization.
checksum_value="$(awk '{print $1}' "$checksum")"
node --input-type=commonjs - "$manifest" "$version" "$build" "$key" "$(basename "$pkg")" "$checksum_value" <<'NODE'
const fs = require('node:fs');
const [output, version, build, key, name, sha256] = process.argv.slice(2);
const artifacts = {
  '/latest-macos.pkg': { key, name, type: 'application/octet-stream', sha256 },
  '/latest-macos.pkg.sha256': { key: `${key}.sha256`, name: `${name}.sha256`, type: 'text/plain; charset=utf-8', sha256 },
};
fs.writeFileSync(output, JSON.stringify({ version, build: Number(build), releaseNotes: '请查看官网更新说明。', artifacts }, null, 2) + '\n');
NODE

cd "$worker_root"
npx wrangler r2 object put "gy-shurufa-releases/$key" --file "$pkg" --content-type application/octet-stream
npx wrangler r2 object put "gy-shurufa-releases/$key.sha256" --file "$checksum" --content-type 'text/plain; charset=utf-8'
npx wrangler r2 object put 'gy-shurufa-releases/releases/macos/latest.json' --file "$manifest" --content-type 'application/json; charset=utf-8'
npx wrangler deploy

echo "Published verified macOS package: https://shurufa.wang/download/latest-macos.pkg"
echo "Update feed: https://shurufa.wang/download/latest-macos.json"
echo "Checksum: https://shurufa.wang/download/latest-macos.pkg.sha256"
