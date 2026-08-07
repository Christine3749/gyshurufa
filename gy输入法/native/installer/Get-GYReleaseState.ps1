[CmdletBinding()]
param(
  [string]$ReleaseApiUrl = 'https://gy-shurufa-download.lihouyi7586.workers.dev/api/releases/latest',
  [switch]$SkipRemote
)

# 一条命令对比三侧版本状态：本机注册表/install-state.json、仓库内 release.json、线上发布 API。
# 只读，不修改任何系统或仓库状态。

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')

function Write-Row([string]$Label, [string]$Value) {
  Write-Host ("  {0,-14}: {1}" -f $Label, $Value)
}

Write-Host "===== 1. 本机运行态 =====" -ForegroundColor Cyan
$local = [ordered]@{ hostVersion = $null; coreVersion = $null; requiresClientReload = $null; tsfRegistered = $null }
try {
  $gy = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\GYInput' -ErrorAction Stop
  $local.hostVersion = [string]$gy.HostPath | ForEach-Object { $_ } ; $local.hostVersion = [string]$gy.HostVersion
  $statePath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent ([string]$gy.HostPath)))) 'install-state.json'
  if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $local.coreVersion = [string]$state.coreVersion
    $local.requiresClientReload = [bool]$state.requiresClientReload
  }
  $server = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Classes\CLSID\{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}\InprocServer32' -ErrorAction SilentlyContinue).'(default)'
  $local.tsfRegistered = [bool](Test-Path -LiteralPath $server -PathType Leaf -ErrorAction SilentlyContinue)
} catch {
  Write-Host "  未检测到本机安装（$($_.Exception.Message)）" -ForegroundColor Yellow
}
Write-Row 'HostVersion' $local.hostVersion
Write-Row 'coreVersion' $local.coreVersion
Write-Row 'needReload' $local.requiresClientReload
Write-Row 'TSF已注册' $local.tsfRegistered

Write-Host "`n===== 2. 仓库内 release.json =====" -ForegroundColor Cyan
$manifestCandidates = @(
  Join-Path $repoRoot 'release\release.json'
  Join-Path $repoRoot 'gy输入法\native\release\GYInput-*\release.json'
)
$repoManifest = $null
foreach ($pattern in $manifestCandidates) {
  $match = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($match) { $repoManifest = Get-Content -LiteralPath $match.FullName -Raw | ConvertFrom-Json; Write-Row '来源文件' $match.FullName; break }
}
if (-not $repoManifest) {
  Write-Host '  未找到 release.json' -ForegroundColor Yellow
} else {
  Write-Row 'channel' $repoManifest.channel
  Write-Row 'windows.version' $repoManifest.windows.version
  Write-Row 'windows.state' $repoManifest.windows.state
  Write-Row 'windows.sha256' $repoManifest.windows.sha256
  Write-Row 'macos.version' $repoManifest.macos.version
  Write-Row 'macos.state' $repoManifest.macos.state
}

Write-Host "`n===== 3. Git 远端可追溯性 =====" -ForegroundColor Cyan
Push-Location $repoRoot
try {
  $remotes = git remote 2>$null
  if (-not $remotes) {
    Write-Host '  未配置任何 git remote —— 无法核对 GitHub/GCP 上是否有同步版本。' -ForegroundColor Yellow
  } else {
    foreach ($r in $remotes) { Write-Row "remote/$r" (git remote get-url $r) }
    $dirty = git status --porcelain
    if ($dirty) { Write-Host "  警告：有未提交的改动，远端不会反映本机最新内容：" -ForegroundColor Yellow; $dirty | ForEach-Object { Write-Host "    $_" } }
  }
} finally { Pop-Location }

Write-Host "`n===== 4. 线上发布 API =====" -ForegroundColor Cyan
if ($SkipRemote) {
  Write-Host '  已跳过（-SkipRemote）'
} else {
  try {
    $remote = Invoke-RestMethod -Uri $ReleaseApiUrl -TimeoutSec 10
    # 注意：线上 API 用 platforms.windows/platforms.macos 包一层，和仓库里 release.json 的顶层 windows/macos 不是同一个形状。
    Write-Row 'windows.version' $remote.platforms.windows.version
    Write-Row 'windows.state' $remote.platforms.windows.state
    Write-Row 'windows.sha256' $remote.platforms.windows.sha256
    Write-Row 'macos.version' $remote.platforms.macos.version
    Write-Row 'macos.state' $remote.platforms.macos.state
  } catch {
    Write-Host "  无法访问 $ReleaseApiUrl：$($_.Exception.Message)" -ForegroundColor Yellow
  }
}

Write-Host "`n===== 结论 =====" -ForegroundColor Cyan
if ($repoManifest -and $local.coreVersion -and $repoManifest.windows.version -ne $local.coreVersion) {
  Write-Host "  [不一致] 本机核心版本 $($local.coreVersion) 与仓库 release.json 版本 $($repoManifest.windows.version) 不同。" -ForegroundColor Red
} elseif ($repoManifest -and $local.coreVersion) {
  Write-Host "  [一致] 本机核心版本与仓库 release.json 均为 $($local.coreVersion)。" -ForegroundColor Green
} else {
  Write-Host '  信息不完整，无法判断本机与仓库是否一致。' -ForegroundColor Yellow
}
if (-not $SkipRemote -and $remote -and $local.coreVersion) {
  if ($remote.platforms.windows.version -ne $local.coreVersion) {
    Write-Host "  [不一致] 本机核心版本 $($local.coreVersion) 与线上 API 版本 $($remote.platforms.windows.version) 不同。" -ForegroundColor Red
  } else {
    Write-Host "  [一致] 本机核心版本与线上 API 均为 $($local.coreVersion)。" -ForegroundColor Green
  }
}
if (-not $remotes) {
  Write-Host '  [待办] 本地仓库没有 git remote，release.json 的改动目前无法验证是否已推送到 GitHub/GCP 的任何仓库。' -ForegroundColor Yellow
}
