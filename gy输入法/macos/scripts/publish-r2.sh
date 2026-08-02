#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
macos_root="$root/macos"
worker_root="$root/../gy输入法---官方网站/download-worker"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$macos_root/GYInput/Resources/Info.plist")"
release_dir="$macos_root/release/$version"
pkg="$release_dir/GYInput-$version-arm64.pkg"
checksum="$pkg.sha256"
key="releases/$version/$(basename "$pkg")"

[[ -f "$pkg" && -f "$checksum" ]] || { echo "Missing notarized package or SHA-256 file in $release_dir" >&2; exit 1; }
command -v npx >/dev/null || { echo "Node.js/npx is required to upload through Wrangler." >&2; exit 1; }
command -v pkgutil >/dev/null || { echo "Run this only on macOS." >&2; exit 1; }
shasum -a 256 -c "$checksum"
pkgutil --check-signature "$pkg"
spctl -a -vv --type install "$pkg"
xcrun stapler validate "$pkg"

cd "$worker_root"
npx wrangler r2 object put "gy-shurufa-releases/$key" --file "$pkg" --content-type application/octet-stream
npx wrangler r2 object put "gy-shurufa-releases/$key.sha256" --file "$checksum" --content-type 'text/plain; charset=utf-8'
npx wrangler deploy

echo "Published verified macOS package: https://shurufa.wang/download/latest.pkg"
echo "Checksum: https://shurufa.wang/download/latest.pkg.sha256"
