#!/usr/bin/env bash
# Keep 剪贴板同步的端到端验证。
#
# 会真实操作系统剪贴板，并在 Keep 里留下一条探针文本（Keep 不删旧记录，
# 所以那条会永久保留）。跑之前请确认你接受这两件事。
set -uo pipefail

app="/Library/Input Methods/GYInput.app"
# v4 起，SQLite（GYBlockStore）才是唯一事实来源；旧 TSV 迁移后改名为
# clipboard-history.tsv.migrated-backup，不再被写入，不能再用来判断同步状态
# （这正是 G-01 事故：脚本曾经把本地 TSV 标记当作服务端唯一真相）。
db_file="$HOME/Library/Application Support/GYInput/sync.sqlite"
settings_file="$HOME/Library/Application Support/GYInput/settings.json"
log_file="$(mktemp -t gy-verify-log)"
pass=0
fail=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=$((fail+1)); }
info() { printf '    %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

head_ "1. 安装与进程"
if [[ -d "$app" ]]; then
  build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist" 2>/dev/null)"
  short="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null)"
  if [[ "${build:-0}" -ge 209 ]]; then ok "已安装 $short (build $build)"
  else bad "已安装 $short (build $build)，低于 209 —— 修复未生效，先装新包"; fi
  for sym in GYKeepSync GYAccountAuth GYBlockStore; do
    if nm -U "$app/Contents/MacOS/GYInput" 2>/dev/null | grep -q "$sym"; then ok "$sym 已编入"
    else bad "$sym 不在二进制里"; fi
  done
else
  bad "没找到 $app"
fi
if pgrep -x GYInput >/dev/null; then ok "GYInput 进程在运行 (pid $(pgrep -x GYInput | head -1))"
else bad "GYInput 没在运行 —— 需要在某个输入框里选中 GY 输入法激活它"; fi

head_ "2. 账号与开关"
if security find-generic-password -s "wang.shurufa.GYInput.gsyen" -a session >/dev/null 2>&1; then
  ok "Keychain 里有 GY 会话（已登录）"
else
  bad "Keychain 里没有会话 —— 未登录，同步不会发生。请在设置→账户页登录"
fi
if [[ -f "$settings_file" ]]; then
  python3 - "$settings_file" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
for k,label in (("clipboardSyncEnabled","Keep 同步"),("clipboardInstantPaste","即时粘贴")):
    v=d.get(k)
    print(f"  {'\033[32m✓\033[0m' if v else '\033[33m!\033[0m'} {label}: {'开' if v else '关'}")
PY
fi

head_ "3. 抓取同步日志（后台 12 秒）"
log stream --predicate 'process == "GYInput"' --style compact >"$log_file" 2>&1 &
log_pid=$!
sleep 1

head_ "4. 复制 → 本机历史 → Keep 确认"
probe="GY-VERIFY-$(date +%s)"
t0=$(python3 -c 'import time;print(time.time())')
printf '%s' "$probe" | pbcopy
info "已复制探针字符串"

captured=""; confirmed=""
for _ in $(seq 1 400); do   # 最多 20 秒
  if [[ -z "$captured" ]] && [[ -f "$db_file" ]] && \
     sqlite3 "$db_file" "SELECT 1 FROM blocks WHERE text='$probe' LIMIT 1;" 2>/dev/null | grep -q 1; then
    captured=$(python3 -c "import time;print(f'{time.time()-$t0:.3f}')")
  fi
  if [[ -n "$captured" ]] && [[ -f "$db_file" ]] && \
     sqlite3 "$db_file" "SELECT 1 FROM blocks WHERE text='$probe' AND state='confirmed' AND sequence IS NOT NULL LIMIT 1;" 2>/dev/null | grep -q 1; then
    confirmed=$(python3 -c "import time;print(f'{time.time()-$t0:.3f}')")
    break
  fi
  sleep 0.05
done

if [[ -n "$captured" ]]; then ok "进入本机历史：${captured}s"
else bad "20 秒内没进本机历史 —— 捕获层有问题"; fi
if [[ -n "$confirmed" ]]; then ok "Keep 确认接收（state=confirmed，sequence 非空）：${confirmed}s"
else bad "20 秒内 Keep 未确认 —— 上传或拉取有问题，或本轮就没跑（见第 6 步日志）"; fi

head_ "5. 截图存活（复制图片后不应被同步覆盖）"
png="$(mktemp -t gy-verify).png"
osascript -e 'tell application "System Events" to return 1' >/dev/null 2>&1
python3 - "$png" <<'PY'
import struct,zlib,sys
def chunk(t,d):
    c=t+d; return struct.pack('>I',len(d))+c+struct.pack('>I',zlib.crc32(c))
raw=b''.join(b'\x00'+b'\xff\x00\x00'*4 for _ in range(4))
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',4,4,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')
open(sys.argv[1],'wb').write(png)
PY
if osascript -e "set the clipboard to (read (POSIX file \"$png\") as «class PNGf»)" >/dev/null 2>&1; then
  info "已把图片放进剪贴板，等待 12 秒看是否被文本覆盖…"
  sleep 12
  if osascript -e 'clipboard info' 2>/dev/null | grep -q "PNGf\|TIFF\|«class PNGf»"; then
    ok "12 秒后剪贴板里仍是图片（截图保护成立）"
  else
    bad "剪贴板已被文本覆盖 —— 截图保护失效"
    info "当前内容类型: $(osascript -e 'clipboard info' 2>/dev/null | head -c 120)"
  fi
  since=$(python3 -c 'import time;print(time.time()-15)')
  if [[ -f "$db_file" ]] && sqlite3 "$db_file" \
      "SELECT 1 FROM blocks WHERE kind='image' AND captured_at > $since LIMIT 1;" 2>/dev/null | grep -q 1; then
    ok "图片作为 kind=image 进入本机历史（不是占位文字）"
  else
    bad "没找到对应的 kind=image 记录 —— 图片捕获没有落库"
  fi
else
  info "（跳过：无法通过 osascript 写入图片剪贴板）"
fi

head_ "6. 同步日志实况"
kill "$log_pid" 2>/dev/null; wait "$log_pid" 2>/dev/null
if grep -q "GY keep:\|GY account:" "$log_file"; then
  grep "GY keep:\|GY account:" "$log_file" | tail -8 | sed 's/^/    /'
  bytes=$(grep -o '[0-9]* bytes' "$log_file" | tail -1 | cut -d' ' -f1)
  if [[ -n "${bytes:-}" ]]; then
    info ""
    if [[ "$bytes" -gt 200000 ]]; then
      bad "拉取载荷 ${bytes} 字节 —— 服务端很可能返回了全部历史而非最新 20 条"
    else
      ok "拉取载荷 ${bytes} 字节，规模正常"
    fi
  fi
else
  bad "12 秒内没有任何 GY 同步日志 —— 同步循环没在跑"
fi

head_ "结果"
printf '  通过 %d 项，失败 %d 项\n' "$pass" "$fail"
printf '  日志留存: %s\n' "$log_file"
printf '  注意: Keep 里多了一条探针 "%s"，Keep 不删旧记录，需要的话请手动删除。\n' "$probe"
[[ "$fail" -eq 0 ]]
