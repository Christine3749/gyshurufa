#!/usr/bin/env bash
# deploy-mac-release.sh — Mac 全量发布一条命令：
#   拉最新代码 → 构建+签名+公证 → 上传 R2 → 提交发布清单。
# 跑完后通知 Windows 侧推进 releases/latest.json（官网 Mac 下载才会解锁）。
#
# 前置（只需配一次，建议写进 ~/.zshrc）：
#   export GY_DEVELOPER_IDENTITY='Developer ID Application: <你的名字> (<TEAMID>)'
#   export GY_INSTALLER_IDENTITY='Developer ID Installer: <你的名字> (<TEAMID>)'
#   export GY_NOTARY_PROFILE='<notarytool keychain profile 名>'
# 另需：npx wrangler 已登录 Cloudflare（R2 上传权限）、git 可推 GitHub。
set -euo pipefail

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$scripts_dir/../../.." && pwd)"
cd "$repo_root"

echo '== 0. 环境预检'
: "${GY_DEVELOPER_IDENTITY:?缺少 GY_DEVELOPER_IDENTITY（Developer ID Application 证书名）}"
: "${GY_INSTALLER_IDENTITY:?缺少 GY_INSTALLER_IDENTITY（Developer ID Installer 证书名）}"
: "${GY_NOTARY_PROFILE:?缺少 GY_NOTARY_PROFILE（notarytool keychain profile）}"
command -v python3 >/dev/null || { echo 'python3 missing' >&2; exit 1; }
command -v npx >/dev/null || { echo 'npx missing' >&2; exit 1; }

echo '== 1. 同步最新代码'
git -C "$repo_root" pull --rebase origin main
if [[ -n "$(git -C "$repo_root" status --porcelain -- gy输入法/macos release)" ]]; then
  echo 'macos/ 或 release/ 有未提交改动，先处理再发布。' >&2
  exit 1
fi

echo '== 2. 构建 + 签名 + 公证（package-release.sh）'
bash "$scripts_dir/package-release.sh"

echo '== 3. 校验并上传 R2（publish-r2.sh）'
bash "$scripts_dir/publish-r2.sh"

echo '== 4. 提交发布清单'
git -C "$repo_root" add release/release.json
git -C "$repo_root" commit -m "release: macOS $(python3 -c 'import json,pathlib;print(json.loads(pathlib.Path("'"$repo_root"'/release/release.json").read_text(encoding="utf-8-sig"))["macos"]["version"])') notarized pkg"
git -C "$repo_root" push origin main

cat <<'EOF'

✅ Mac 包已上传 R2（不可变版本对象）。
还差最后一步（在 Windows 侧执行，或叫助手做）：
  推进 releases/latest.json —— 官网 Mac 下载按钮才会亮。
EOF
