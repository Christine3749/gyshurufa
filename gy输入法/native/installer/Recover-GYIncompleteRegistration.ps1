[CmdletBinding()]
param(
  [switch]$LockAlreadyHeld,
  [string]$InstallRoot = ''
)

# Repairs only missing Host metadata for an already active, health-checked GY
# version. It never registers a TSF DLL, starts a Host, changes the keyboard
# list, deletes files, or records user input. The caller must own the global
# activation transaction for the whole check-and-write sequence.

$ErrorActionPreference = 'Stop'
if (-not $LockAlreadyHeld) {
  throw 'Incomplete-registration recovery is installer-only and requires the activation transaction lock.'
}

if (-not $InstallRoot) {
  $programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
  $InstallRoot = Join-Path $programFiles 'GYInput'
}
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$statePath = Join-Path $InstallRoot 'install-state.json'

function Read-RegisteredString([string]$SubKey, [string]$ValueName) {
  $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($SubKey)
  if (-not $key) { return '' }
  try { return [string]$key.GetValue($ValueName, '') } finally { $key.Dispose() }
}

function Get-StateString([object]$State, [string]$Name) {
  $property = if ($State) { $State.PSObject.Properties[$Name] } else { $null }
  if (-not $property) { return '' }
  return [string]$property.Value
}

function Test-SamePath([string]$Left, [string]$Right) {
  return [string]::Equals($Left, $Right, [StringComparison]::OrdinalIgnoreCase)
}

function Test-ManagedPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  try {
    $root = $InstallRoot + '\'
    $full = [IO.Path]::GetFullPath($Path)
    return $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)
  } catch {
    return $false
  }
}

$classKey = 'Software\Classes\CLSID\{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}\InprocServer32'
$registeredDll = Read-RegisteredString $classKey ''
$registeredHost = Read-RegisteredString 'Software\GYInput' 'HostPath'
$registeredVersion = Read-RegisteredString 'Software\GYInput' 'HostVersion'

# A first install has no registration to recover. A complete registration is
# left untouched and is verified by the normal installer rollback checks.
if (-not $registeredDll -and -not $registeredHost -and -not $registeredVersion) { exit 0 }
if ($registeredHost -and $registeredVersion) { exit 0 }
if (-not $registeredDll) {
  throw 'GY Host metadata exists without an active TSF DLL; refusing automatic recovery.'
}
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
  throw 'The active GY DLL has no durable install state from which Host metadata can be recovered.'
}

$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$version = Get-StateString $state 'version'
$hostVersion = Get-StateString $state 'hostVersion'
$coreVersion = Get-StateString $state 'coreVersion'
$dll = Get-StateString $state 'dll'
$host = Get-StateString $state 'host'
$health = Get-StateString $state 'health'
$activationState = Get-StateString $state 'activationState'

if ([int]$state.schemaVersion -ne 2 -or $activationState -ne 'active' -or
    $state.registryVerified -ne $true -or $state.requiresClientReload -ne $false) {
  throw 'Durable GY state is not a verified active snapshot; refusing automatic recovery.'
}
if ($version -notmatch '^\d+\.\d+\.\d+$' -or $hostVersion -ne $version -or $coreVersion -ne $version) {
  throw 'Durable GY state has inconsistent DLL and Host versions.'
}

$expectedDll = Join-Path $InstallRoot "tsf-$version\GyIme.dll"
$expectedHost = Join-Path $InstallRoot "versions\$version\GyImeHost-$version.exe"
$expectedHealth = Join-Path $InstallRoot "versions\$version\GyImeHealth-$version.exe"
if (-not (Test-ManagedPath $dll) -or -not (Test-ManagedPath $host) -or
    -not (Test-ManagedPath $health) -or -not (Test-SamePath $dll $expectedDll) -or
    -not (Test-SamePath $host $expectedHost) -or -not (Test-SamePath $health $expectedHealth) -or
    -not (Test-Path -LiteralPath $dll -PathType Leaf) -or
    -not (Test-Path -LiteralPath $host -PathType Leaf) -or
    -not (Test-Path -LiteralPath $health -PathType Leaf)) {
  throw 'Durable GY state references missing, unexpected, or unmanaged files.'
}
if (-not (Test-SamePath $registeredDll $dll)) {
  throw 'The registered GY DLL does not match the durable active snapshot.'
}
if (($registeredHost -and -not (Test-SamePath $registeredHost $host)) -or
    ($registeredVersion -and $registeredVersion -ne $version)) {
  throw 'Existing partial GY Host metadata conflicts with the durable active snapshot.'
}

$healthResult = Start-Process -FilePath $health -WorkingDirectory (Split-Path -Parent $health) `
  -Wait -PassThru -WindowStyle Hidden
if ($healthResult.ExitCode -ne 0) {
  throw "The active GY rollback target failed its offline health check (exit code: $($healthResult.ExitCode))."
}

$hostKey = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('Software\GYInput')
if (-not $hostKey) { throw 'Unable to open the GY Host registry key for recovery.' }
$valueNames = @($hostKey.GetValueNames())
$hadHost = $valueNames -contains 'HostPath'
$hadVersion = $valueNames -contains 'HostVersion'
$oldHost = if ($hadHost) { $hostKey.GetValue('HostPath') } else { $null }
$oldHostKind = if ($hadHost) { $hostKey.GetValueKind('HostPath') } else { $null }
$oldVersion = if ($hadVersion) { $hostKey.GetValue('HostVersion') } else { $null }
$oldVersionKind = if ($hadVersion) { $hostKey.GetValueKind('HostVersion') } else { $null }
try {
  $hostKey.SetValue('HostPath', $host, [Microsoft.Win32.RegistryValueKind]::String)
  $hostKey.SetValue('HostVersion', $version, [Microsoft.Win32.RegistryValueKind]::String)
  if (-not (Test-SamePath ([string]$hostKey.GetValue('HostPath', '')) $host) -or
      [string]$hostKey.GetValue('HostVersion', '') -ne $version) {
    throw 'Recovered GY Host registry values failed readback verification.'
  }
} catch {
  if ($hadHost) { $hostKey.SetValue('HostPath', $oldHost, $oldHostKind) }
  else { $hostKey.DeleteValue('HostPath', $false) }
  if ($hadVersion) { $hostKey.SetValue('HostVersion', $oldVersion, $oldVersionKind) }
  else { $hostKey.DeleteValue('HostVersion', $false) }
  throw
} finally {
  $hostKey.Dispose()
}

exit 0
