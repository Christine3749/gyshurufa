param([switch]$Elevated)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'GYInputTransaction.ps1')
$programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$installRoot = Join-Path $programFiles 'GYInput'
$previousPath = Join-Path $installRoot 'install-state.previous.json'
$currentPath = Join-Path $installRoot 'install-state.json'
$pendingPath = Join-Path $installRoot 'pending-activation.json'
$taskName = 'GYInput\ActivatePending'
$taskNameLogon = 'GYInput\ActivatePendingLogon'

function Get-X64RegSvr32 {
  if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { return Join-Path $env:WINDIR 'Sysnative\regsvr32.exe' }
  return Join-Path $env:WINDIR 'System32\regsvr32.exe'
}

function Test-ManagedGyPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  try {
    $root = [IO.Path]::GetFullPath($installRoot).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath($Path)
    return $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)
  } catch { return $false }
}

function Set-ActiveGyHost([string]$HostPath, [string]$HostVersion) {
  if (-not (Test-ManagedGyPath $HostPath)) { throw 'Rollback refused: Host is outside the managed GYInput directory.' }
  $key = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('Software\GYInput')
  try {
    $key.SetValue('HostPath', $HostPath, [Microsoft.Win32.RegistryValueKind]::String)
    $key.SetValue('HostVersion', $HostVersion, [Microsoft.Win32.RegistryValueKind]::String)
  } finally { $key.Dispose() }
}


function Write-GyStateAtomically([object]$State, [string]$Path) {
  $directory = Split-Path -Parent $Path
  $temporary = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
  try {
    [IO.File]::WriteAllText($temporary, ($State | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
  }
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $Elevated) {
  $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Elevated"
  $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait -PassThru
  if ($process.ExitCode -ne 0) { throw "GY rollback failed; elevated PowerShell returned $($process.ExitCode)." }
  Write-Host 'GY Input Method was restored to the previous verified version. Close and reopen input applications to use it.'
  exit 0
}
Invoke-WithGYInputTransaction {
if (-not $isAdmin) { throw 'Rollback requires administrator permission.' }
$currentState = if (Test-Path -LiteralPath $currentPath -PathType Leaf) {
  Get-Content -LiteralPath $currentPath -Raw | ConvertFrom-Json
} else { $null }
if ($currentState) {
  $currentState.activationState = 'rollback'
  $currentState.registryVerified = $false
  $currentState.requiresClientReload = $true
  Write-GyStateAtomically $currentState $currentPath
}
Remove-GYInputScheduledTask $taskName | Out-Null
Remove-GYInputScheduledTask $taskNameLogon | Out-Null
Remove-Item -LiteralPath $pendingPath -Force -ErrorAction SilentlyContinue
if (-not (Test-Path -LiteralPath $previousPath -PathType Leaf)) { throw 'No verified previous GY version is available for rollback.' }

$previous = Get-Content -LiteralPath $previousPath -Raw | ConvertFrom-Json
$dll = [string]$previous.dll
$hostPath = [string]$previous.host
$hostVersion = [string]$previous.version
$health = [string]$previous.health
if (-not (Test-ManagedGyPath $dll) -or -not (Test-ManagedGyPath $hostPath) -or
    -not (Test-ManagedGyPath $health) -or -not (Test-Path -LiteralPath $dll -PathType Leaf) -or
    -not (Test-Path -LiteralPath $hostPath -PathType Leaf) -or -not (Test-Path -LiteralPath $health -PathType Leaf)) {
  throw 'Rollback state is incomplete or references an unmanaged GY file.'
}

$healthResult = Start-Process -FilePath $health -WorkingDirectory (Split-Path -Parent $health) -Wait -PassThru
if ($healthResult.ExitCode -ne 0) { throw "Previous version health check failed; rollback was not applied (exit code: $($healthResult.ExitCode))." }
$restore = Start-Process -FilePath (Get-X64RegSvr32) -ArgumentList ('/s "{0}"' -f $dll) -Wait -PassThru
if ($restore.ExitCode -ne 0) { throw "Previous GY TSF connector could not be registered (regsvr32 exit code: $($restore.ExitCode))." }
Set-ActiveGyHost $hostPath $hostVersion
if (Test-Path -LiteralPath $currentPath -PathType Leaf) {
  Copy-Item -LiteralPath $currentPath -Destination (Join-Path $installRoot 'install-state.rolled-back.json') -Force
}
$restoredState = [ordered]@{
  schemaVersion = 2
  version = $hostVersion
  hostVersion = $hostVersion
  coreVersion = [IO.Path]::GetFileName((Split-Path -Parent $dll)).Replace('tsf-','')
  installedAtUtc = [DateTime]::UtcNow.ToString('o')
  dll = $dll
  host = $hostPath
  health = $health
  updateModel = 'versioned-tsf-host'
  activationState = 'active'
  registryVerified = $true
  requiresClientReload = $false
  previousCoreVersion = $null
}
Write-GyStateAtomically $restoredState $currentPath
Write-Host 'GY Input Method rollback completed. Close and reopen input applications to use the restored version.'
}
