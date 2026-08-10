[CmdletBinding()]
param(
  [ValidateSet('Check', 'Install')]
  [string]$Action = 'Check',
  [string]$ReleaseApiUrl = 'https://gy-shurufa-download.lihouyi7586.workers.dev/api/releases/latest',
  [string]$ExpectedVersion = '',
  [switch]$Force
)

# GY 自动升级入口：
# 1. Check 只读取官方发布 API，并把结果写入当前用户的本地状态文件；
# 2. Install 先下载、校验版本/字节数/SHA-256/Authenticode 签名，再启动标准 EXE；
# 3. 安装器自身负责管理员 UAC、事务锁、pending 和 Finalizer 激活。
# 输入过程中绝不调用此脚本，也不上传输入内容。

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Get-InstalledGyRoot {
  try {
    $gy = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\GYInput' -ErrorAction Stop
    $hostPath = [string]$gy.HostPath
    if ([string]::IsNullOrWhiteSpace($hostPath)) { return $null }
    $versionRoot = Split-Path -Parent $hostPath
    $versionsRoot = Split-Path -Parent $versionRoot
    return Split-Path -Parent $versionsRoot
  } catch {
    return $null
  }
}

function Get-InstalledVersion {
  $root = Get-InstalledGyRoot
  if (-not $root) { return $null }
  try {
    $value = [string](Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\GYInput' -Name HostVersion -ErrorAction Stop)
    $parsed = $null
    if ([version]::TryParse($value, [ref]$parsed)) { return $parsed }
  } catch { }
  return $null
}

function Get-StatePath {
  $base = Join-Path $env:LOCALAPPDATA 'GYInput'
  New-Item -ItemType Directory -Path $base -Force | Out-Null
  return Join-Path $base 'update-state.ini'
}

function Write-State([hashtable]$Values) {
  $path = Get-StatePath
  $lines = foreach ($key in @('schemaVersion','checkedAtUtc','currentVersion','available','version','status','downloadUrl','sha256','bytes','error')) {
    if ($Values.ContainsKey($key)) {
      $value = [string]$Values[$key]
      $value = $value.Replace("`r", ' ').Replace("`n", ' ')
      "{0}={1}" -f $key, $value
    }
  }
  $temporary = "$path.$([guid]::NewGuid().ToString('N')).tmp"
  Set-Content -LiteralPath $temporary -Value $lines -Encoding UTF8
  Move-Item -LiteralPath $temporary -Destination $path -Force
}

function Get-StateValue([string]$Name) {
  $path = Get-StatePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
  $line = Get-Content -LiteralPath $path -ErrorAction SilentlyContinue | Where-Object { $_ -like "$Name=*" } | Select-Object -First 1
  if (-not $line) { return '' }
  return [string]$line.Substring($Name.Length + 1)
}

function Get-VersionText($Value) {
  if ($null -eq $Value) { return '' }
  $text = [string]$Value
  $parsed = $null
  if (-not [version]::TryParse($text, [ref]$parsed)) { throw "版本号无效：$text" }
  if ($parsed.Revision -ge 0 -or $parsed.Build -ge 0) { return $parsed.ToString(3) }
  throw "版本号无效：$text"
}

function Get-ReleaseInfo {
  $api = [Uri]$ReleaseApiUrl
  if ($api.Scheme -ne 'https' -or $api.AbsolutePath -ne '/api/releases/latest') {
    throw '更新 API 必须是 HTTPS 的 /api/releases/latest 官方接口。'
  }
  $remote = Invoke-RestMethod -Uri $api.AbsoluteUri -Method Get -TimeoutSec 15 -Headers @{
    'Accept' = 'application/json'
    'User-Agent' = 'GYInput-AutoUpdate/1'
  }
  $asset = $remote.platforms.windows
  if (-not $asset -or -not [bool]$asset.available) { throw '官方发布服务暂未提供可验证的 Windows 版本。' }
  $versionText = Get-VersionText $asset.version
  $filename = [string]$asset.filename
  if ($filename -ne "GYInputSetup-$versionText.exe") { throw 'Windows 安装器文件名与版本不一致。' }
  if ([string]$asset.state -notin @('candidate','signed','notarized','stable')) { throw 'Windows 版本尚未通过发布状态校验。' }
  if ([string]$asset.sha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'Windows 安装器缺少有效 SHA-256。' }
  $bytes = [int64]$asset.bytes
  if ($bytes -le 0) { throw 'Windows 安装器字节数无效。' }
  $downloadPath = [string]$asset.downloadUrl
  if ($downloadPath -notmatch '^/download/windows/\d+\.\d+\.\d+$') { throw '下载地址不是受控的版本化 Windows 下载路径。' }
  $downloadUri = [Uri]::new($api, $downloadPath)
  if ($downloadUri.Host -ne $api.Host -or $downloadUri.Scheme -ne 'https') { throw '下载地址未与官方 API 使用同一 HTTPS 来源。' }
  [pscustomobject]@{
    Api = $api
    Version = [version]$versionText
    VersionText = $versionText
    Filename = $filename
    Bytes = $bytes
    Sha256 = ([string]$asset.sha256).ToUpperInvariant()
    State = [string]$asset.state
    DownloadUri = $downloadUri
  }
}

function Invoke-Check {
  $now = [DateTime]::UtcNow.ToString('o')
  $current = Get-InstalledVersion
  if (-not $Force) {
    $previous = $null
    if ([DateTime]::TryParse((Get-StateValue 'checkedAtUtc'), [Globalization.DateTimeStyles]::RoundtripKind, [ref]$previous) -and
        $previous.ToUniversalTime().AddHours(6) -gt [DateTime]::UtcNow) {
      return 0
    }
  }
  try {
    if (-not $current) {
      Write-State @{ schemaVersion = 1; checkedAtUtc = $now; currentVersion = ''; available = 0; version = ''; status = 'not-installed'; downloadUrl = ''; sha256 = ''; bytes = 0; error = '' }
      return 0
    }
    $release = Get-ReleaseInfo
    $available = $release.Version -gt $current
    $status = if ($available) { 'update-available' } else { 'up-to-date' }
    Write-State @{ schemaVersion = 1; checkedAtUtc = $now; currentVersion = $current.ToString(3); available = [int]$available; version = $release.VersionText; status = $status; downloadUrl = $release.DownloadUri.AbsoluteUri; sha256 = $release.Sha256; bytes = $release.Bytes; error = '' }
    return 0
  } catch {
    Write-State @{ schemaVersion = 1; checkedAtUtc = $now; currentVersion = if ($current) { $current.ToString(3) } else { '' }; available = 0; version = ''; status = 'check-failed'; downloadUrl = ''; sha256 = ''; bytes = 0; error = $_.Exception.Message }
    return 2
  }
}

function Invoke-Install {
  $current = Get-InstalledVersion
  $release = $null
  try {
    if (-not $current) { throw '未检测到已安装的 GY 输入法。' }
    $release = Get-ReleaseInfo
    if (-not $Force -and $release.Version -le $current) {
      Write-State @{ schemaVersion = 1; checkedAtUtc = [DateTime]::UtcNow.ToString('o'); currentVersion = $current.ToString(3); available = 0; version = $release.VersionText; status = 'up-to-date'; downloadUrl = $release.DownloadUri.AbsoluteUri; sha256 = $release.Sha256; bytes = $release.Bytes; error = '' }
      return 0
    }
    if ($ExpectedVersion -and $release.VersionText -ne (Get-VersionText $ExpectedVersion)) { throw '线上版本已变化，请重新检查后再安装。' }
    $downloadRoot = Join-Path $env:LOCALAPPDATA "GYInput\updates\$($release.VersionText)"
    New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
    $installer = Join-Path $downloadRoot $release.Filename
    Invoke-WebRequest -Uri $release.DownloadUri.AbsoluteUri -OutFile $installer -UseBasicParsing -TimeoutSec 300
    $actualBytes = (Get-Item -LiteralPath $installer).Length
    if ($actualBytes -ne $release.Bytes) { throw "安装器字节数校验失败：$actualBytes / $($release.Bytes)。" }
    $actualHash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualHash -ne $release.Sha256) { throw '安装器 SHA-256 校验失败，已删除不可信文件。' }
    $signature = Get-AuthenticodeSignature -LiteralPath $installer
    if ($signature.Status -ne 'Valid') { throw "安装器签名校验失败：$($signature.Status)。未启动安装。" }
    Write-State @{ schemaVersion = 1; checkedAtUtc = [DateTime]::UtcNow.ToString('o'); currentVersion = $current.ToString(3); available = 1; version = $release.VersionText; status = 'ready-to-install'; downloadUrl = $release.DownloadUri.AbsoluteUri; sha256 = $release.Sha256; bytes = $release.Bytes; error = '' }
    Start-Process -FilePath $installer -Verb RunAs -WorkingDirectory $downloadRoot | Out-Null
    Write-State @{ schemaVersion = 1; checkedAtUtc = [DateTime]::UtcNow.ToString('o'); currentVersion = $current.ToString(3); available = 1; version = $release.VersionText; status = 'installer-launched'; downloadUrl = $release.DownloadUri.AbsoluteUri; sha256 = $release.Sha256; bytes = $release.Bytes; error = '' }
    return 0
  } catch {
    $versionText = if ($release) { $release.VersionText } else { '' }
    $downloadUrl = if ($release) { $release.DownloadUri.AbsoluteUri } else { '' }
    $sha = if ($release) { $release.Sha256 } else { '' }
    $bytes = if ($release) { $release.Bytes } else { 0 }
    Write-State @{ schemaVersion = 1; checkedAtUtc = [DateTime]::UtcNow.ToString('o'); currentVersion = if ($current) { $current.ToString(3) } else { '' }; available = [int]([bool]$release); version = $versionText; status = 'install-failed'; downloadUrl = $downloadUrl; sha256 = $sha; bytes = $bytes; error = $_.Exception.Message }
    return 3
  }
}

if ($Action -eq 'Install') { exit (Invoke-Install) }
exit (Invoke-Check)
