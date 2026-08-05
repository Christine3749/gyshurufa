# Prune-GYOldVersions.ps1 — GY 输入法升级/卸载时的旧版本剪除器
#
# 契约：
#   * 只删除本脚本自己判定为"旧版本目录"的东西（versions\<ver> 与 tsf-<ver>），
#     以及 {InstallRoot}\pending-prune.txt 中登记的遗留项。永不触碰用户数据
#     （%LOCALAPPDATA%\GYInput 下的 settings.ini、学习库等不在这里）。
#   * 升级时由安装器调用：保留当前版与回滚版（N 与 N-1），剪除其余。
#   * 卸载时由卸载器调用（-All）：剪除全部版本目录与状态文件。
#   * 被进程映射锁住的文件：改名后重试；仍失败则登记到 pending-prune.txt，
#     下次安装/卸载时先扫尾。不需要重启系统。
param(
  [string]$InstallRoot = "C:\Program Files\GYInput",
  # Comma-separated single string: powershell.exe -File binds only one value
  # per parameter, so a real [string[]] can never receive two versions.
  [string]$KeepVersions = "",
  [switch]$All
)
$ErrorActionPreference = 'Continue'
$keepList = @($KeepVersions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })

function Remove-GYPathRobust([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $true }
  try {
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    return $true
  } catch {
    # 有文件被进程映射：可改名不可删，先逐个挪名再整体删
    Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
      try { Rename-Item -LiteralPath $_.FullName -NewName ($_.Name + ".trash") -Force -ErrorAction Stop } catch {}
    }
    try {
      Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
      return $true
    } catch {
      return $false
    }
  }
}

$pendingFile = Join-Path $InstallRoot 'pending-prune.txt'

# 1. 先扫尾：处理上一次没删干净的遗留项
if (Test-Path -LiteralPath $pendingFile) {
  $stillThere = @()
  foreach ($entry in (Get-Content -LiteralPath $pendingFile -ErrorAction SilentlyContinue)) {
    if ([string]::IsNullOrWhiteSpace($entry)) { continue }
    if (-not (Remove-GYPathRobust $entry.Trim())) { $stillThere += $entry.Trim() }
  }
  if ($stillThere) { $stillThere | Set-Content -LiteralPath $pendingFile -Encoding ascii }
  else { Remove-Item -LiteralPath $pendingFile -Force -ErrorAction SilentlyContinue }
}

# 2. 收集本轮目标
$targets = @()
if ($All) {
  foreach ($dir in (Get-ChildItem -LiteralPath $InstallRoot -Directory -ErrorAction SilentlyContinue)) {
    if ($dir.Name -eq 'versions' -or $dir.Name -like 'tsf-*') { $targets += $dir.FullName }
  }
  $targets += (Join-Path $InstallRoot 'install-state.json')
  $targets += (Join-Path $InstallRoot 'install-state.previous.json')
} else {
  $versionsRoot = Join-Path $InstallRoot 'versions'
  if (Test-Path -LiteralPath $versionsRoot) {
    foreach ($v in (Get-ChildItem -LiteralPath $versionsRoot -Directory -ErrorAction SilentlyContinue)) {
      if ($keepList -notcontains $v.Name) { $targets += $v.FullName }
    }
  }
  foreach ($dir in (Get-ChildItem -LiteralPath $InstallRoot -Directory -ErrorAction SilentlyContinue)) {
    if ($dir.Name -match '^tsf-(.+)$' -and ($keepList -notcontains $Matches[1])) { $targets += $dir.FullName }
  }
}

# 3. 执行剪除，失败者登记留待下次
$failed = @()
foreach ($t in $targets) {
  if (-not (Remove-GYPathRobust $t)) { $failed += $t }
}
if ($failed) {
  $existing = @()
  if (Test-Path -LiteralPath $pendingFile) { $existing = @(Get-Content -LiteralPath $pendingFile -ErrorAction SilentlyContinue) }
  ($existing + $failed) | Sort-Object -Unique | Set-Content -LiteralPath $pendingFile -Encoding ascii
}
exit 0
