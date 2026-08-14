[CmdletBinding()]
param(
  [ValidateSet('Check', 'Install')]
  [string]$Action = 'Check',
  [string]$ReleaseApiUrl = 'https://gy-shurufa-download.lihouyi7586.workers.dev/api/releases/latest',
  [string]$ExpectedVersion = '',
  [string]$ToastActionUri = '',
  [switch]$Force
)

# GY 自动升级入口：
# 1. Check 会在确认可用时预下载并校验安装器（不执行安装）；
# 2. Install 优先复用已缓存安装器，只在需要时补下载，再启动标准 EXE；
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

function Get-UpdateCacheRoot {
  $root = Join-Path $env:LOCALAPPDATA 'GYInput\updates'
  New-Item -ItemType Directory -Path $root -Force | Out-Null
  return $root
}

function Get-UpdatePackagePath([pscustomobject]$Release) {
  return Join-Path (Join-Path (Get-UpdateCacheRoot) $Release.VersionText) $Release.Filename
}

function Test-UpdatePackage([pscustomobject]$Release, [string]$Path) {
  $path = $Path
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  $actualBytes = (Get-Item -LiteralPath $path).Length
  if ($actualBytes -ne $Release.Bytes) { return $null }
  $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
  if ($actualHash -ne $Release.Sha256) { return $null }
  $signature = Get-AuthenticodeSignature -LiteralPath $path
  if ($signature.Status -ne 'Valid') { return $null }
  return $path
}

function Get-UpdatePackage([pscustomobject]$Release) {
  return Test-UpdatePackage $Release (Get-UpdatePackagePath $Release)
}

function Ensure-UpdatePackage {
  param([pscustomobject]$Release)
  $path = Get-UpdatePackagePath $Release
  $parent = Split-Path -Path $path -Parent
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
  $cached = Get-UpdatePackage $Release
  if ($cached) { return $cached }
  # Do not expose a partly-downloaded EXE as the reusable cache entry. The
  # versioned cache path only appears after byte size, SHA-256 and signature
  # validation all pass.
  $temporary = "$path.$([guid]::NewGuid().ToString('N')).download"
  try {
    Invoke-WebRequest -Uri $Release.DownloadUri.AbsoluteUri -OutFile $temporary -UseBasicParsing -TimeoutSec 300
    $prepared = Test-UpdatePackage $Release $temporary
    if (-not $prepared) { throw '安装包下载后校验失败。' }
    Move-Item -LiteralPath $temporary -Destination $path -Force
    $cached = Get-UpdatePackage $Release
    if (-not $cached) { throw '安装包缓存提交后校验失败。' }
    return $cached
  } finally {
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
  }
}

function Write-State([hashtable]$Values) {
  $path = Get-StatePath
  $lexicon = Get-EnglishLexiconState
  $lines = foreach ($key in @('schemaVersion','checkedAtUtc','currentVersion','available','version','status','downloadUrl','sha256','bytes','snoozeUntilUtc','lexiconStatus','lexiconVersion','lexiconSyncedAtUtc','lexiconError','error')) {
    if ($Values.ContainsKey($key)) {
      $value = [string]$Values[$key]
    } elseif ($key -eq 'lexiconStatus') {
      $value = [string]$lexicon.Status
    } elseif ($key -eq 'lexiconVersion') {
      $value = [string]$lexicon.Version
    } elseif ($key -eq 'lexiconSyncedAtUtc') {
      $value = [string]$lexicon.SyncedAtUtc
    } elseif ($key -eq 'lexiconError') {
      $value = [string]$lexicon.Error
    } else {
      continue
    }
    $value = $value.Replace("`r", ' ').Replace("`n", ' ')
    "{0}={1}" -f $key, $value
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

function Get-EnglishLexiconState {
  $result = [ordered]@{ Status = 'not-installed'; Version = ''; SyncedAtUtc = ''; Error = '' }
  $path = Join-Path $env:LOCALAPPDATA 'GYInput\lexicons\english-mixed\english-mixed-state.ini'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return [pscustomobject]$result }
  foreach ($line in Get-Content -LiteralPath $path -ErrorAction SilentlyContinue) {
    $separator = $line.IndexOf('=')
    if ($separator -le 0) { continue }
    $key = $line.Substring(0, $separator)
    $value = $line.Substring($separator + 1).Replace("`r", ' ').Replace("`n", ' ')
    if ($key -eq 'status') { $result.Status = $value }
    elseif ($key -eq 'activeVersion') { $result.Version = $value }
    elseif ($key -eq 'syncedAtUtc') { $result.SyncedAtUtc = $value }
    elseif ($key -eq 'error') { $result.Error = $value }
  }
  return [pscustomobject]$result
}

function Invoke-EnglishLexiconSync {
  $script = Join-Path $PSScriptRoot 'Sync-GYEnglishLexicon.ps1'
  if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { return Get-EnglishLexiconState }
  try {
    $process = Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -Wait -PassThru -WindowStyle Hidden -ArgumentList (
      '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $script)
    $state = Get-EnglishLexiconState
    if ($process.ExitCode -ne 0 -and [string]::IsNullOrWhiteSpace($state.Error)) {
      $state.Error = '英文词库同步未完成，继续使用上次本地词库。'
    }
    return $state
  } catch {
    return [pscustomobject]@{ Status = 'failed'; Version = ''; SyncedAtUtc = ''; Error = $_.Exception.Message }
  }
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
  $snoozeUntil = $null
  if (-not $Force -and [DateTime]::TryParse((Get-StateValue 'snoozeUntilUtc'), [Globalization.DateTimeStyles]::RoundtripKind, [ref]$snoozeUntil) -and
      $snoozeUntil.ToUniversalTime() -gt [DateTime]::UtcNow) {
    return 0
  }
  if (-not $Force) {
    $previous = $null
    if ([DateTime]::TryParse((Get-StateValue 'checkedAtUtc'), [Globalization.DateTimeStyles]::RoundtripKind, [ref]$previous) -and
        $previous.ToUniversalTime().AddHours(6) -gt [DateTime]::UtcNow) {
      return 0
    }
  }
  try {
    if (-not $current) {
      Write-State @{ schemaVersion = 1; checkedAtUtc = $now; currentVersion = ''; available = 0; version = ''; status = 'not-installed'; downloadUrl = ''; sha256 = ''; bytes = 0; snoozeUntilUtc = ''; error = '' }
      return 0
    }
    $release = Get-ReleaseInfo
    # A successful update check is the only automatic refresh trigger. This is
    # a separate, bounded child process; its failure never blocks an update nor
    # affects the active offline candidate snapshot.
    $null = Invoke-EnglishLexiconSync
    $available = $release.Version -gt $current
    if ($available) {
      $installer = Ensure-UpdatePackage $release
      if (-not (Test-Path -LiteralPath $installer)) { throw '安装包未完成准备。' }
      Write-State @{
        schemaVersion = 1
        checkedAtUtc = $now
        currentVersion = $current.ToString(3)
        available = 1
        version = $release.VersionText
        status = 'ready-to-install'
        downloadUrl = $release.DownloadUri.AbsoluteUri
        sha256 = $release.Sha256
        bytes = $release.Bytes
        snoozeUntilUtc = ''
        error = ''
      }
      return 0
    }
    $status = 'up-to-date'
    Write-State @{ schemaVersion = 1; checkedAtUtc = $now; currentVersion = $current.ToString(3); available = [int]$available; version = $release.VersionText; status = $status; downloadUrl = $release.DownloadUri.AbsoluteUri; sha256 = $release.Sha256; bytes = $release.Bytes; snoozeUntilUtc = ''; error = '' }
    return 0
  } catch {
    Write-State @{ schemaVersion = 1; checkedAtUtc = $now; currentVersion = if ($current) { $current.ToString(3) } else { '' }; available = 0; version = ''; status = 'check-failed'; downloadUrl = ''; sha256 = ''; bytes = 0; snoozeUntilUtc = ''; error = $_.Exception.Message }
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
      Write-State @{ schemaVersion = 1; checkedAtUtc = [DateTime]::UtcNow.ToString('o'); currentVersion = $current.ToString(3); available = 0; version = $release.VersionText; status = 'up-to-date'; downloadUrl = $release.DownloadUri.AbsoluteUri; sha256 = $release.Sha256; bytes = $release.Bytes; snoozeUntilUtc = ''; error = '' }
      return 0
    }
    if ($ExpectedVersion -and $release.VersionText -ne (Get-VersionText $ExpectedVersion)) { throw '线上版本已变化，请重新检查后再安装。' }
    $installer = Ensure-UpdatePackage $release
    Write-State @{ schemaVersion = 1; checkedAtUtc = [DateTime]::UtcNow.ToString('o'); currentVersion = $current.ToString(3); available = 1; version = $release.VersionText; status = 'ready-to-install'; downloadUrl = $release.DownloadUri.AbsoluteUri; sha256 = $release.Sha256; bytes = $release.Bytes; snoozeUntilUtc = ''; error = '' }
    $downloadRoot = Split-Path -Parent $installer
    Start-Process -FilePath $installer -Verb RunAs -WorkingDirectory $downloadRoot | Out-Null
    Write-State @{ schemaVersion = 1; checkedAtUtc = [DateTime]::UtcNow.ToString('o'); currentVersion = $current.ToString(3); available = 1; version = $release.VersionText; status = 'installer-launched'; downloadUrl = $release.DownloadUri.AbsoluteUri; sha256 = $release.Sha256; bytes = $release.Bytes; snoozeUntilUtc = ''; error = '' }
    return 0
  } catch {
    $versionText = if ($release) { $release.VersionText } else { '' }
    $downloadUrl = if ($release) { $release.DownloadUri.AbsoluteUri } else { '' }
    $sha = if ($release) { $release.Sha256 } else { '' }
    $bytes = if ($release) { $release.Bytes } else { 0 }
    Write-State @{ schemaVersion = 1; checkedAtUtc = [DateTime]::UtcNow.ToString('o'); currentVersion = if ($current) { $current.ToString(3) } else { '' }; available = [int]([bool]$release); version = $versionText; status = 'install-failed'; downloadUrl = $downloadUrl; sha256 = $sha; bytes = $bytes; snoozeUntilUtc = ''; error = $_.Exception.Message }
    return 3
  }
}

function Invoke-Snooze {
  $version = Get-StateValue 'version'
  $current = Get-StateValue 'currentVersion'
  if ([string]::IsNullOrWhiteSpace($version)) { return 0 }
  $marker = Join-Path (Split-Path -Parent (Get-StatePath)) 'update-notified.txt'
  Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
  Write-State @{ schemaVersion = 1; checkedAtUtc = [DateTime]::UtcNow.ToString('o'); currentVersion = $current; available = 1; version = $version; status = 'snoozed'; downloadUrl = Get-StateValue 'downloadUrl'; sha256 = Get-StateValue 'sha256'; bytes = [int64](Get-StateValue 'bytes'); snoozeUntilUtc = [DateTime]::UtcNow.AddHours(24).ToString('o'); error = '' }
  return 0
}

if ($ToastActionUri -eq 'gyinput://update/install') { exit (Invoke-Install) }
if ($ToastActionUri -eq 'gyinput://update/snooze') { exit (Invoke-Snooze) }
if ($Action -eq 'Install') { exit (Invoke-Install) }
exit (Invoke-Check)
