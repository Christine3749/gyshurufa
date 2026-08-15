[CmdletBinding()]
param(
  [string]$InstallRoot,
  [string]$CurrentVersion,
  [switch]$PlanOnly
)

# Releases through 0.10.90 used a version-qualified Inno Setup AppId.  Windows
# therefore retained a separate Add/Remove Programs entry for every upgrade.
# This migration is deliberately narrow: it removes only verified legacy GY
# uninstall entries and their matching uninstaller folders.  It never touches
# TSF registration, active binaries, user language settings, or user data.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
  $programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
  $InstallRoot = Join-Path $programFiles 'GYInput'
}
if ($CurrentVersion -and $CurrentVersion -notmatch '^\d+\.\d+\.\d+$') {
  throw "Invalid current GY version: $CurrentVersion"
}

function Get-NormalizedPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
  try { return [IO.Path]::GetFullPath($Path).TrimEnd('\') }
  catch { return '' }
}

$normalizedInstallRoot = Get-NormalizedPath $InstallRoot
if (-not $normalizedInstallRoot) { throw 'GY install root is invalid.' }

function Test-ManagedInstallRoot([string]$Path) {
  return [string]::Equals((Get-NormalizedPath $Path), $normalizedInstallRoot,
                           [StringComparison]::OrdinalIgnoreCase)
}

$uninstallSubKey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
$legacyKeyPattern = '^GYInput-(\d+\.\d+\.\d+)_is1$'
$expectedDisplayName = 'GY ' + [char]0x8F93 + [char]0x5165 + [char]0x6CD5
$registryViews = if ([Environment]::Is64BitOperatingSystem) {
  @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)
} else {
  @([Microsoft.Win32.RegistryView]::Default)
}

$legacyVersions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$removedRegistryEntries = [System.Collections.Generic.List[string]]::new()
$removedUninstallerFolders = [System.Collections.Generic.List[string]]::new()
$skippedEntries = [System.Collections.Generic.List[string]]::new()

foreach ($view in $registryViews) {
  $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
  try {
    $writable = -not [bool]$PlanOnly
    $uninstallKey = $baseKey.OpenSubKey($uninstallSubKey, $writable)
    if (-not $uninstallKey) { continue }
    try {
      foreach ($keyName in @($uninstallKey.GetSubKeyNames())) {
        if ($keyName -notmatch $legacyKeyPattern) { continue }
        $version = $Matches[1]
        $entry = $uninstallKey.OpenSubKey($keyName)
        if (-not $entry) { continue }
        try {
          $displayName = [string]$entry.GetValue('DisplayName')
          $installLocation = [string]$entry.GetValue('InstallLocation')
          if ($displayName -ne $expectedDisplayName -or -not (Test-ManagedInstallRoot $installLocation)) {
            $skippedEntries.Add("${view}:$keyName")
            continue
          }
        } finally {
          $entry.Dispose()
        }

        [void]$legacyVersions.Add($version)
        if ($PlanOnly) {
          $removedRegistryEntries.Add("${view}:$keyName (planned)")
          continue
        }
        $uninstallKey.DeleteSubKeyTree($keyName)
        $removedRegistryEntries.Add("${view}:$keyName")
      }
    } finally {
      $uninstallKey.Dispose()
    }
  } finally {
    $baseKey.Dispose()
  }
}

foreach ($version in @($legacyVersions | Sort-Object {[version]$_})) {
  $legacyFolder = Join-Path $normalizedInstallRoot "uninstall-$version"
  $normalizedLegacyFolder = Get-NormalizedPath $legacyFolder
  if (-not $normalizedLegacyFolder -or
      -not $normalizedLegacyFolder.StartsWith($normalizedInstallRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to clean an unmanaged legacy uninstaller path: $legacyFolder"
  }
  if (-not (Test-Path -LiteralPath $normalizedLegacyFolder -PathType Container)) { continue }
  if ($PlanOnly) {
    $removedUninstallerFolders.Add("$normalizedLegacyFolder (planned)")
    continue
  }
  Remove-Item -LiteralPath $normalizedLegacyFolder -Recurse -Force
  $removedUninstallerFolders.Add($normalizedLegacyFolder)
}

[pscustomobject][ordered]@{
  installRoot = $normalizedInstallRoot
  currentVersion = $CurrentVersion
  registryEntries = @($removedRegistryEntries)
  uninstallerFolders = @($removedUninstallerFolders)
  skippedEntries = @($skippedEntries)
  planOnly = [bool]$PlanOnly
} | ConvertTo-Json -Depth 4 -Compress
