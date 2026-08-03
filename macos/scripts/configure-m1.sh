#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
macos_root="$root/macos"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "GYInput macOS can only be configured on a Mac." >&2
  exit 1
fi

if [[ "$(uname -m)" != "arm64" && "${GY_ALLOW_UNIVERSAL:-0}" != "1" ]]; then
  echo "This first target is Apple Silicon only. Set GY_ALLOW_UNIVERSAL=1 only after testing both architectures." >&2
  exit 1
fi
workspace=(default.yaml luna_pinyin.prism.bin luna_pinyin.reverse.bin luna_pinyin.schema.yaml luna_pinyin.table.bin)
for file in "${workspace[@]}"; do
  if [[ ! -f "$root/native/runtime/rime/shared/build/$file" ]]; then
    echo "Bundled Rime workspace is incomplete: missing $file" >&2
    exit 1
  fi
done


command -v xcodebuild >/dev/null || { echo "Install the full Xcode app first (Command Line Tools alone are not enough)." >&2; exit 1; }
xcodebuild -version >/dev/null 2>&1 || { echo "Select a full Xcode installation with xcode-select; Command Line Tools alone cannot build GYInput." >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "Install XcodeGen, then rerun this script." >&2; exit 1; }

mkdir -p "$macos_root/GYInput/Resources/rime-data"
rsync -a --delete "$root/native/runtime/rime/shared/" "$macos_root/GYInput/Resources/rime-data/"
# Windows GY uses five candidate cells per collapsed row and a fixed 5 × 5
# expanded grid. Ask Rime for one expanded grid at a time; the IMK controller
# slices that page into five-cell rows for normal paging, while preserving
# 1–5 selection for the current row. These
# are staged copies only; Windows' shared runtime is never modified.
for config in \
  "$macos_root/GYInput/Resources/rime-data/default.yaml" \
  "$macos_root/GYInput/Resources/rime-data/luna_pinyin.schema.yaml" \
  "$macos_root/GYInput/Resources/rime-data/build/default.yaml" \
  "$macos_root/GYInput/Resources/rime-data/build/luna_pinyin.schema.yaml"; do
  perl -0pi -e 's/(^menu:\R[ \t]+page_size:\s*)\d+/${1}25/mg' "$config"
  # The Mac panel is a five-column grid but never limits the text length of a
  # candidate. Enable phrase/sentence candidates in the staged macOS schema
  # only; Windows continues to use its own shared Rime runtime unchanged.
  perl -0pi -e 's/(^translator:\R[ \t]+dictionary:[^\R]*\R)/$1  enable_sentence: true\n/mg' "$config"
done
printf '%s\n' 'candidate-grid-5x5-v2-opencc' > "$macos_root/GYInput/Resources/rime-data/workspace.version"

cd "$macos_root"
xcodegen generate
echo "Generated $macos_root/GYInputMac.xcodeproj"
echo "Next: ./scripts/build-macos.sh (it stages arm64 librime and produces GYInput.app)."
