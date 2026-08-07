#!/usr/bin/env bash
set -euo pipefail

# GY 输入法 · 完全卸载（macOS，需要 sudo 运行）
# 用法：sudo bash uninstall-gyinput.sh
# 清掉：程序本体（系统级+用户级）、预览版/残骸、LaunchServices 登记、缓存。
# 保留：~/Library/Rime 用户词库与学习数据（如需一并删除，脚本末尾有注释行）。

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

# 缓存刷新链（与 postinstall 同一条链）
/usr/bin/sudo -u "$login_user" /usr/bin/killall TextInputMenuAgent 2>/dev/null || true
/usr/bin/sudo -u "$login_user" /usr/bin/killall SystemUIServer 2>/dev/null || true
/usr/bin/sudo -u "$login_user" /usr/bin/killall cfprefsd 2>/dev/null || true
/usr/bin/killall iconservicesagent 2>/dev/null || true
/usr/bin/killall iconservicesd 2>/dev/null || true

echo "完成。用户词库保留在 /Users/$login_user/Library/Rime（要一起删：mv 到废纸篓即可）。"
