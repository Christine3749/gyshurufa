#!/usr/bin/env bash
set -euo pipefail

# GY 输入法 · 完全卸载（macOS，需要 sudo 运行）
# 用法：sudo bash uninstall-gyinput.sh [--purge-data]
# 清掉：程序本体（系统级+用户级）、预览版/残骸、LaunchServices 登记、
#       安装收据、缓存。
# 加 --purge-data 还会删除 ~/Library/Application Support/GYInput，
#       也就是设置、剪贴板历史和 Rime 用户目录。
# 始终保留：~/Library/Rime。
#
# 装新版之前建议先在 系统设置 → 键盘 → 输入法 里把 GY 移除，
# 那是唯一可靠地清掉 AppleEnabledInputSources 里旧条目的方式；
# 直接改那份 plist 容易把输入法列表搞坏。

purge_data=0
for arg in "$@"; do
  case "$arg" in
    --purge-data) purge_data=1 ;;
    *) echo "未知参数: $arg" >&2; exit 2 ;;
  esac
done

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "请以 root 运行：sudo bash $0" >&2
  exit 1
fi

login_user="$(/usr/bin/stat -f '%Su' /dev/console)"
IME_DIR="/Library/Input Methods"
USER_IME_DIR="/Users/$login_user/Library/Input Methods"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

/usr/bin/pkill -x GYInput || true
/usr/bin/pkill -x GYInputPreview || true
for _ in 1 2 3; do
  /usr/bin/pgrep -x GYInput >/dev/null || break
  /bin/sleep 1
done

shopt -s nullglob
copies=(
  "$IME_DIR/GYInput.app"
  "$IME_DIR"/GYInputPreview*.app
  "$IME_DIR"/GYInput*.failed*
  "$IME_DIR"/GYInput*.rollback*
  "$USER_IME_DIR/GYInput.app"
  "$USER_IME_DIR"/GYInputPreview*.app
)
removed=0
for item in "${copies[@]}"; do
  [[ -e "$item" ]] || continue
  "$LSREGISTER" -u "$item" >/dev/null 2>&1 || true
  /bin/rm -rf "$item"
  echo "已删除: $item"
  removed=$((removed + 1))
done
[[ "$removed" -eq 0 ]] && echo "没有找到 GYInput 副本。"

# 安装收据。不清掉的话，installer 会拿收据里的版本号跟新包比对，
# 判定新包是降级后**静默跳过**——日志里只有一行 "Skipping component"，
# 表面上却显示 "The upgrade was successful"。历史上这些 ID 都用过。
for receipt in \
  wang.shurufa.GYInput.core \
  wang.shurufa.GYInput.pkg \
  wang.shurufa.GYInput.pkg.local \
  wang.shurufa.GYInput.beta \
  wang.shurufa.GYInputPreview.core \
  wang.shurufa.inputmethod.GYInput; do
  if /usr/sbin/pkgutil --pkg-info "$receipt" >/dev/null 2>&1; then
    /usr/sbin/pkgutil --forget "$receipt" >/dev/null 2>&1 && echo "已清除安装收据: $receipt"
  fi
done

if [[ "$purge_data" -eq 1 ]]; then
  support="/Users/$login_user/Library/Application Support/GYInput"
  if [[ -d "$support" ]]; then
    /bin/rm -rf "$support"
    echo "已删除用户数据: $support（设置、剪贴板历史、Rime 用户目录）"
  fi
fi

# 缓存刷新链（与 postinstall 同一条链）
/usr/bin/sudo -u "$login_user" /usr/bin/killall TextInputMenuAgent 2>/dev/null || true
/usr/bin/sudo -u "$login_user" /usr/bin/killall SystemUIServer 2>/dev/null || true
/usr/bin/sudo -u "$login_user" /usr/bin/killall cfprefsd 2>/dev/null || true
/usr/bin/killall iconservicesagent 2>/dev/null || true
/usr/bin/killall iconservicesd 2>/dev/null || true

echo
echo "完成。用户词库保留在 /Users/$login_user/Library/Rime（要一起删：mv 到废纸篓即可）。"
if [[ "$purge_data" -eq 0 ]]; then
  echo "设置与剪贴板历史保留在 Application Support/GYInput；要一并清除请加 --purge-data。"
fi
echo "接着装新版之前，确认一下这里是空的："
echo "  pkgutil --pkgs | grep shurufa"
