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
param([string]$InstallRoot = 'C:\Program Files\GYInput', [string]$KeepVersions = '', [switch]$All)
$ErrorActionPreference = 'Continue'
$keepList = @($KeepVersions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })

function Get-GYOldSiblingPath([string]$Path) {
  $directory = Split-Path -Parent $Path
  $leaf = Split-Path -Leaf $Path
  for ($i = 0; $i -lt 1000; $i++) {
    $candidate = Join-Path $directory ($leaf + '.old.' + $i)
    if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
  }
  return $null
}

function Preserve-GYLockedFiles([string]$Path) {
  Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $file = $_
    try {
      $probe = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
      $probe.Dispose()
    } catch {
      $fileSibling = Get-GYOldSiblingPath $file.FullName
      if ($fileSibling) {
        try { Copy-Item -LiteralPath $file.FullName -Destination $fileSibling -Force -ErrorAction Stop } catch {}
      }
    }
  }
}

function Remove-GYPathRobust([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $true }
  # Probe and preserve unreadably shared DLLs before a failed recursive delete
  # can place them in delete-pending state.
  Preserve-GYLockedFiles $Path
  try {
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    return $true
  } catch {
    # A loaded DLL may deny deletion but still permit a directory/file rename.
    # Preserve the complete old payload under .old.N instead of deleting it.
    if ($Path -notmatch '\.old\.\d+$') {
      $sibling = Get-GYOldSiblingPath $Path
      if ($sibling) {
        try {
          Rename-Item -LiteralPath $Path -NewName (Split-Path -Leaf $sibling) -Force -ErrorAction Stop
          return $true
        } catch {}
      }
    }

    # If the directory itself cannot be renamed, preserve any files that can
    # move and leave the still-locked original path in pending-prune.txt.
    Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
      $file = $_
      if ($file.Name -match '\.old\.\d+$') { return }
      $fileSibling = Get-GYOldSiblingPath $file.FullName
      if (-not $fileSibling) { return }
      try {
        Rename-Item -LiteralPath $file.FullName -NewName (Split-Path -Leaf $fileSibling) -Force -ErrorAction Stop
      } catch {
        try { Copy-Item -LiteralPath $file.FullName -Destination $fileSibling -Force -ErrorAction Stop } catch {}
      }
    }
    # Keep the original path queued when any locked part remains. The .old.N
    # artifacts are intentionally retained as safe recovery evidence.
    return $false
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
    if ($dir.Name -eq 'versions' -or $dir.Name -match '^versions\.old\.\d+$' -or $dir.Name -like 'tsf-*') {
      $targets += $dir.FullName
    }
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
    # A locked versions root can be renamed to versions.old.N during a prior
    # cleanup attempt.  It is never an active path, so a later verified repair
    # may safely retry it alongside stale tsf-* siblings.
    if ($dir.Name -match '^versions\.old\.\d+$') { $targets += $dir.FullName }
    elseif ($dir.Name -match '^tsf-(.+)$' -and ($keepList -notcontains $Matches[1])) { $targets += $dir.FullName }
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
