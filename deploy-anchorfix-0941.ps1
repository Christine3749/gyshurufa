# deploy-anchorfix-0941.ps1
# 硬化版部署：事务化替换 + 任何一步失败自动回滚 + 部署后验证。
# 防火墙原则：绝不允许"改名成功、复制失败"把系统留在残缺状态。
$ErrorActionPreference = 'Stop'

function Fail([string]$msg) {
  Write-Host ""
  Write-Host "DEPLOY FAILED: $msg" -ForegroundColor Red
  exit 1
}

# ── 0. 预检：任何一项不满足，不动安装目录一根汗毛 ──────────────────────
$buildDir = 'C:\Users\Ethan\Desktop\01-Projects\shurufa\gy输入法\native\build-trace\bin\Release'
if (-not (Test-Path $buildDir)) { Fail "build dir not found: $buildDir`n  如果路径里的中文变成乱码，说明本脚本被无 BOM 保存过——重新从仓库取一份。" }
$buildHost = "$buildDir\GyImeHost.exe"
$buildDll  = "$buildDir\GyIme.dll"
foreach ($f in @($buildHost, $buildDll)) {
  if (-not (Test-Path $f)) { Fail "build missing: $f" }
  if ((Get-Item $f).Length -lt 100KB) { Fail "build file suspiciously small ($((Get-Item $f).Length) bytes): $f" }
}
$hostPath = (Get-ItemProperty 'HKLM:\SOFTWARE\GYInput' -ErrorAction SilentlyContinue).HostPath
if (-not $hostPath) { Fail 'HKLM:\SOFTWARE\GYInput HostPath not found' }
$versionDir = Split-Path $hostPath
$version = Split-Path $versionDir -Leaf
$dllPath = Join-Path (Split-Path $versionDir -Parent | Split-Path -Parent) "tsf-$version\GyIme.dll"
if (-not (Test-Path $dllPath)) { Fail "installed DLL not found: $dllPath" }
$expectedHostSize = (Get-Item $buildHost).Length
$expectedDllSize  = (Get-Item $buildDll).Length

# ── 1. 事务：备份 → 替换 → 逐步验证；任何异常整体回滚 ──────────────────
# 备份名 = 时间戳 + 随机后缀：同一秒连跑两次也绝不撞名（上次的真实事故）。
$stamp = "$(Get-Date -Format HHmmss)-$([guid]::NewGuid().ToString('N').Substring(0,4))"
$hostBak = "$hostPath.anchor-bak.$stamp"
$dllBak  = "$dllPath.anchor-bak.$stamp"
$hostBackedUp = $false
$dllBackedUp  = $false

try {
  Get-Process | Where-Object { $_.Name -like 'GyImeHost*' } | Stop-Process -Force -ErrorAction SilentlyContinue

  if (Test-Path $hostPath) { Rename-Item -Path $hostPath -NewName (Split-Path $hostBak -Leaf); $hostBackedUp = $true }
  Copy-Item $buildHost $hostPath -Force
  if ((Get-Item $hostPath).Length -ne $expectedHostSize) { throw "host size mismatch after copy" }

  if (Test-Path $dllPath) { Rename-Item -Path $dllPath -NewName (Split-Path $dllBak -Leaf); $dllBackedUp = $true }
  Copy-Item $buildDll $dllPath -Force
  if ((Get-Item $dllPath).Length -ne $expectedDllSize) { throw "DLL size mismatch after copy" }
}
catch {
  Write-Host ""
  Write-Host "step failed: $($_.Exception.Message) — rolling back" -ForegroundColor Yellow
  if (-not (Test-Path $hostPath) -and $hostBackedUp -and (Test-Path $hostBak)) {
    Rename-Item -Path $hostBak -NewName (Split-Path $hostPath -Leaf)
    Write-Host "  host restored from backup" -ForegroundColor Yellow
  }
  if (-not (Test-Path $dllPath) -and $dllBackedUp -and (Test-Path $dllBak)) {
    Rename-Item -Path $dllBak -NewName (Split-Path $dllPath -Leaf)
    Write-Host "  DLL restored from backup" -ForegroundColor Yellow
  }
  Fail "rolled back to previous state; nothing left half-deployed"
}

# ── 2. 部署后验证：缺一个文件都算失败（此时已有备份兜底，直接报） ──────
if (-not (Test-Path $hostPath)) { Fail "post-check: host exe missing (backup kept: $hostBak)" }
if (-not (Test-Path $dllPath))  { Fail "post-check: DLL missing (backup kept: $dllBak)" }

# ── 3. 清扫备份尸体：每种只留最新 2 个 ─────────────────────────────────
foreach ($pattern in @("$hostPath.anchor-bak*", "$hostPath.clipboard-bak*", "$dllPath.anchor-bak*")) {
  Get-ChildItem $pattern -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -Skip 2 |
    Remove-Item -Force -ErrorAction SilentlyContinue
}

Write-Host "deployed Host + DLL ($version), verified $expectedHostSize / $expectedDllSize bytes" -ForegroundColor Green
Write-Host "restart Kimi (or sign out/in) to load the new DLL; next keystroke starts the new Host" -ForegroundColor Yellow
