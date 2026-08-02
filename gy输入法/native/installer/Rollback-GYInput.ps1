param([switch]$Elevated)

$ErrorActionPreference = 'Stop'
$programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$installRoot = Join-Path $programFiles 'GYInput'
$previousPath = Join-Path $installRoot 'install-state.previous.json'
$currentPath = Join-Path $installRoot 'install-state.json'

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
if (-not $isAdmin) { throw 'Rollback requires administrator permission.' }
if (-not (Test-Path -LiteralPath $previousPath -PathType Leaf)) { throw 'No verified previous GY version is available for rollback.' }

$previous = Get-Content -LiteralPath $previousPath -Raw | ConvertFrom-Json
$dll = [string]$previous.dll
$host = [string]$previous.host
$hostVersion = [string]$previous.version
$health = [string]$previous.health
if (-not (Test-ManagedGyPath $dll) -or -not (Test-ManagedGyPath $host) -or
    -not (Test-ManagedGyPath $health) -or -not (Test-Path -LiteralPath $dll -PathType Leaf) -or
    -not (Test-Path -LiteralPath $host -PathType Leaf) -or -not (Test-Path -LiteralPath $health -PathType Leaf)) {
  throw 'Rollback state is incomplete or references an unmanaged GY file.'
}

$healthResult = Start-Process -FilePath $health -WorkingDirectory (Split-Path -Parent $health) -Wait -PassThru
if ($healthResult.ExitCode -ne 0) { throw "Previous version health check failed; rollback was not applied (exit code: $($healthResult.ExitCode))." }
$restore = Start-Process -FilePath (Get-X64RegSvr32) -ArgumentList ('/s "{0}"' -f $dll) -Wait -PassThru
if ($restore.ExitCode -ne 0) { throw "Previous GY TSF connector could not be registered (regsvr32 exit code: $($restore.ExitCode))." }
Set-ActiveGyHost $host $hostVersion
if (Test-Path -LiteralPath $currentPath -PathType Leaf) {
  Copy-Item -LiteralPath $currentPath -Destination (Join-Path $installRoot 'install-state.rolled-back.json') -Force
}
$previous | ConvertTo-Json | Set-Content -LiteralPath $currentPath -Encoding utf8
Write-Host 'GY Input Method rollback completed. Close and reopen input applications to use the restored version.'