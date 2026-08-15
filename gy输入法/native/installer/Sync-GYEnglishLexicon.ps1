[CmdletBinding()]
param(
  [string]$ManifestUrl = 'https://gy-shurufa-download.lihouyi7586.workers.dev/api/ciku/ime/manifest',
  [switch]$AllowLocalTestEndpoint
)

# GY English lexicon sync is explicitly outside the typing path. It downloads
# a public, versioned snapshot only after the updater has completed a release
# check. Every malformed or failed refresh keeps the previously-ready snapshot.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:LexiconRoot = Join-Path $env:LOCALAPPDATA 'GYInput\lexicons\english-mixed'
$script:StatePath = Join-Path $script:LexiconRoot 'english-mixed-state.ini'
$script:MaximumBytes = 16MB
$script:MaximumEntries = 250000
$script:LexiconId = 'gy-ime-english-mixed'
$script:LexiconFormat = 'gy-ime-english-v1'

function Get-NowUtc { return [DateTime]::UtcNow.ToString('o') }

function Test-ExactOfficialUri([Uri]$Uri, [string]$Path) {
  return $Uri -and $Uri.Scheme -eq 'https' -and
    $Uri.Host.Equals('gy-shurufa-download.lihouyi7586.workers.dev', [StringComparison]::OrdinalIgnoreCase) -and
    $Uri.Port -eq 443 -and $Uri.AbsolutePath -eq $Path -and [string]::IsNullOrEmpty($Uri.Query) -and
    [string]::IsNullOrEmpty($Uri.Fragment) -and [string]::IsNullOrEmpty($Uri.UserInfo)
}

function Test-AllowedUri([Uri]$Uri, [string]$Path) {
  if (Test-ExactOfficialUri $Uri $Path) { return $true }
  return $AllowLocalTestEndpoint -and $Uri -and $Uri.Scheme -eq 'http' -and
    $Uri.Host -eq '127.0.0.1' -and $Uri.Port -eq 8794 -and $Uri.AbsolutePath -eq $Path -and
    [string]::IsNullOrEmpty($Uri.Query) -and [string]::IsNullOrEmpty($Uri.Fragment) -and
    [string]::IsNullOrEmpty($Uri.UserInfo)
}

function Get-StateValues {
  $values = @{
    syncedAtUtc = ''
    activeVersion = ''
    sha256 = ''
    bytes = ''
    entryCount = ''
  }
  if (-not (Test-Path -LiteralPath $script:StatePath -PathType Leaf)) { return $values }
  foreach ($line in Get-Content -LiteralPath $script:StatePath -ErrorAction SilentlyContinue) {
    $separator = $line.IndexOf('=')
    if ($separator -le 0) { continue }
    $values[$line.Substring(0, $separator)] = $line.Substring($separator + 1)
  }
  return $values
}

function Write-State([hashtable]$Values) {
  New-Item -ItemType Directory -Path $script:LexiconRoot -Force | Out-Null
  $ordered = @('schemaVersion', 'checkedAtUtc', 'syncedAtUtc', 'status', 'activeVersion', 'sha256', 'bytes', 'entryCount', 'error')
  $lines = foreach ($key in $ordered) {
    $value = if ($Values.ContainsKey($key)) { [string]$Values[$key] } else { '' }
    "{0}={1}" -f $key, $value.Replace("`r", ' ').Replace("`n", ' ')
  }
  $temporary = "$script:StatePath.$([guid]::NewGuid().ToString('N')).tmp"
  Set-Content -LiteralPath $temporary -Value $lines -Encoding utf8
  Move-Item -LiteralPath $temporary -Destination $script:StatePath -Force
}

function Get-Manifest {
  $uri = [Uri]$ManifestUrl
  if (-not (Test-AllowedUri $uri '/api/ciku/ime/manifest')) {
    throw 'English lexicon manifest must use the official GY download Worker HTTPS endpoint.'
  }
  $headers = @{
    'Accept' = 'application/json'
    'User-Agent' = 'GYInput-EnglishLexicon/1'
  }
  $manifest = Invoke-RestMethod -Uri $uri.AbsoluteUri -Method Get -TimeoutSec 20 -Headers $headers
  if ($null -eq $manifest -or [int]$manifest.schemaVersion -ne 1 -or
      [string]$manifest.id -ne $script:LexiconId -or [string]$manifest.format -ne $script:LexiconFormat) {
    throw 'English lexicon manifest has an invalid schema.'
  }
  $version = [string]$manifest.version
  if ($version -notmatch '^\d{4}\.\d{2}\.\d{2}\.\d{1,6}$') { throw 'English lexicon manifest version is invalid.' }
  $sha256 = ([string]$manifest.sha256).ToUpperInvariant()
  if ($sha256 -notmatch '^[A-F0-9]{64}$') { throw 'English lexicon manifest is missing a valid SHA-256.' }
  $bytes = [Int64]$manifest.bytes
  if ($bytes -le 0 -or $bytes -gt $script:MaximumBytes) { throw 'English lexicon manifest size is outside the safe limit.' }
  $entryCount = [Int64]$manifest.entryCount
  if ($entryCount -le 0 -or $entryCount -gt $script:MaximumEntries) { throw 'English lexicon manifest entry count is outside the safe limit.' }
  $downloadPath = [string]$manifest.downloadUrl
  if ($downloadPath -ne "/api/ciku/ime/lexicon/$version") { throw 'English lexicon download path is not the controlled versioned path.' }
  $downloadUri = [Uri]::new($uri, $downloadPath)
  if (-not (Test-AllowedUri $downloadUri $downloadPath)) { throw 'English lexicon download does not retain the official HTTPS origin.' }
  return [pscustomobject]@{
    Version = $version
    Sha256 = $sha256
    Bytes = $bytes
    EntryCount = $entryCount
    DownloadUri = $downloadUri
  }
}

function Test-LexiconFile([string]$Path, [pscustomobject]$Manifest) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  if ((Get-Item -LiteralPath $Path).Length -ne $Manifest.Bytes) { return $false }
  if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() -ne $Manifest.Sha256) { return $false }
  $count = 0
  $words = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($line in Get-Content -LiteralPath $Path -Encoding utf8) {
    $word = $line.Trim()
    if ($word -notmatch '^[A-Za-z][A-Za-z0-9+._''-]{2,63}$' -or -not $words.Add($word)) { return $false }
    $count += 1
    if ($count -gt $script:MaximumEntries) { return $false }
  }
  return $count -eq $Manifest.EntryCount
}

function Invoke-Sync {
  $now = Get-NowUtc
  $previous = Get-StateValues
  $temporary = ''
  try {
    $manifest = Get-Manifest
    $versionRoot = Join-Path (Join-Path $script:LexiconRoot 'versions') $manifest.Version
    $finalPath = Join-Path $versionRoot 'english.tsv'
    if (Test-LexiconFile $finalPath $manifest) {
      Write-State @{
        schemaVersion = 1; checkedAtUtc = $now; syncedAtUtc = if ($previous.syncedAtUtc) { $previous.syncedAtUtc } else { $now }
        status = 'ready'; activeVersion = $manifest.Version; sha256 = $manifest.Sha256; bytes = $manifest.Bytes
        entryCount = $manifest.EntryCount; error = ''
      }
      return 0
    }
    New-Item -ItemType Directory -Path $versionRoot -Force | Out-Null
    $temporary = "$finalPath.$([guid]::NewGuid().ToString('N')).download"
    try {
      $headers = @{
        'Accept' = 'text/plain'
        'User-Agent' = 'GYInput-EnglishLexicon/1'
      }
      Invoke-WebRequest -Uri $manifest.DownloadUri.AbsoluteUri -OutFile $temporary -UseBasicParsing -TimeoutSec 45 -Headers $headers
      if (-not (Test-LexiconFile $temporary $manifest)) { throw 'English lexicon download did not pass verification.' }
      Move-Item -LiteralPath $temporary -Destination $finalPath -Force
      if (-not (Test-LexiconFile $finalPath $manifest)) { throw 'English lexicon snapshot did not pass verification after activation.' }
    } finally {
      Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
    Write-State @{
      schemaVersion = 1; checkedAtUtc = $now; syncedAtUtc = $now; status = 'ready'; activeVersion = $manifest.Version
      sha256 = $manifest.Sha256; bytes = $manifest.Bytes; entryCount = $manifest.EntryCount; error = ''
    }
    return 0
  } catch {
    # Do not overwrite activeVersion or its snapshot: a failure is observational,
    # not a reason to erase a working offline English candidate list.
    Write-State @{
      schemaVersion = 1; checkedAtUtc = $now; syncedAtUtc = [string]$previous.syncedAtUtc; status = if ($previous.activeVersion) { 'ready' } else { 'failed' }
      activeVersion = [string]$previous.activeVersion; sha256 = [string]$previous.sha256; bytes = [string]$previous.bytes
      entryCount = [string]$previous.entryCount; error = $_.Exception.Message
    }
    return 2
  } finally {
    if ($temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
  }
}

exit (Invoke-Sync)
