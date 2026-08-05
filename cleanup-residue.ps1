# cleanup-residue.ps1 — 清理 0.9.39 残留与调试尸体（需要管理员 PowerShell）
# 保留：0.9.40 正式文件、用户数据（settings.ini / rime userdb）
# 删除：0.9.39 全部目录、0.9.40 目录内的 .old/.bak/.trace-bak 调试文件
$ErrorActionPreference = 'Continue'
$root = "C:\Program Files\GYInput"

Write-Host "== 1. 停掉可能还在跑的 0.9.39 进程" -ForegroundColor Cyan
Get-Process | Where-Object { $_.Name -match "0\.9\.39" } | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host "== 2. 删除 0.9.39 版本目录（回滚目标，如删除失败会改名后重试）" -ForegroundColor Cyan
foreach ($dir in @("$root\versions\0.9.39", "$root\tsf-0.9.39")) {
  if (-not (Test-Path $dir)) { Write-Host "  已不存在: $dir"; continue }
  try {
    Remove-Item $dir -Recurse -Force -ErrorAction Stop
    Write-Host "  已删除: $dir"
  } catch {
    # 有文件被进程映射：先逐个改名再删
    Get-ChildItem $dir -Recurse -File | ForEach-Object {
      $trash = $_.FullName + ".trash"
      try { Rename-Item $_.FullName ($_.Name + ".trash") -Force -ErrorAction Stop } catch {}
    }
    try { Remove-Item $dir -Recurse -Force -ErrorAction Stop; Write-Host "  已删除(改名后): $dir" }
    catch { Write-Warning "  仍有锁定文件，注销重登后再跑一次本脚本即可: $dir" }
  }
}

Write-Host "== 3. 删除 0.9.40 目录内的调试尸体" -ForegroundColor Cyan
$junk = @(
  "$root\tsf-0.9.40\GyIme.dll.old",
  "$root\tsf-0.9.40\GyIme.dll.trace-bak.081818",
  "$root\tsf-0.9.40\GyIme.dll.trace-bak.081858",
  "$root\versions\0.9.40\GyImeHost-0.9.40.exe.old",
  "$root\versions\0.9.40\GyImeHost-0.9.40.exe.old-085255"
)
foreach ($f in $junk) {
  if (Test-Path $f) {
    try { Remove-Item $f -Force -ErrorAction Stop; Write-Host "  已删除: $(Split-Path $f -Leaf)" }
    catch {
      try { Rename-Item $f ((Split-Path $f -Leaf) + ".trash") -Force -ErrorAction Stop; Remove-Item ($f + ".trash") -Force -ErrorAction Stop; Write-Host "  已删除(改名后): $(Split-Path $f -Leaf)" }
      catch { Write-Warning "  锁定中，注销后可删: $(Split-Path $f -Leaf)" }
    }
  }
}

Write-Host "== 4. 移除指向 0.9.39 的回滚清单（目标已不存在）" -ForegroundColor Cyan
if (Test-Path "$root\install-state.previous.json") {
  Remove-Item "$root\install-state.previous.json" -Force
  Write-Host "  已删除: install-state.previous.json（如需回滚可从 shurufa.wang 重装旧版）"
}

Write-Host "== 5. 剩余内容" -ForegroundColor Cyan
Get-ChildItem $root -Recurse -Depth 1 -File | ForEach-Object { "  " + $_.FullName.Replace($root, '') }
Write-Host "完成。" -ForegroundColor Green
