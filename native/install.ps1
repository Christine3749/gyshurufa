param(
  [switch]$Uninstall,
  [switch]$Elevated
)

$ErrorActionPreference = 'Stop'
$tipId = '0804:{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}{5F689D3E-73E3-4C2B-979A-2DD86E438D6F}'
$installRoot = Join-Path $env:ProgramFiles 'GYInput'
# Always use the 64-bit registration host for the x64 TSF DLL, even if this script was started by a 32-bit shell.
$regsvr32 = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
  Join-Path $env:WINDIR 'Sysnative\regsvr32.exe'
} else {
  Join-Path $env:WINDIR 'System32\regsvr32.exe'
}
# TSF DLLs are loaded into every target process.  Use side-by-side versioning so an update never needs to kill user apps.
$installVersion = (Get-Content -LiteralPath (Join-Path  'VERSION') -Raw).Trim()
$installedDll = Join-Path $installRoot ("GyIme-$installVersion.dll")
$legacyUserClsid = 'HKCU:\Software\Classes\CLSID\{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}'

function Update-CurrentUserKeyboardList {
  $languages = Get-WinUserLanguageList
  $chinese = $null
  foreach ($language in $languages) {
    if ($language.LanguageTag -eq 'zh-Hans-CN') { $chinese = $language; break }
  }
  if (-not $chinese) { throw 'Simplified Chinese (China) is not installed. Add it in Windows Settings first.' }

  if ($Uninstall) {
    foreach ($language in $languages) { [void]$language.InputMethodTips.Remove($tipId) }
  } elseif ($chinese.InputMethodTips -notcontains $tipId) {
    [void]$chinese.InputMethodTips.Add($tipId)
  }
  Set-WinUserLanguageList -LanguageList $languages -Force
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $Elevated) {
  $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Elevated"
  if ($Uninstall) { $arguments += ' -Uninstall' }
  $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait -PassThru
  if ($process.ExitCode -ne 0) { throw "GY system operation failed. Elevated PowerShell returned $($process.ExitCode)." }

  Update-CurrentUserKeyboardList
  if ($Uninstall) {
    Write-Host 'GY Input Method removed from the Windows keyboard list.'
  } else {
    Write-Host 'GY Input Method installed. Press Win+Space and select GY Input Method (Pinyin).'
  }
  exit 0
}

if (-not $isAdmin) { throw 'Administrator permission is required for the system TSF registration.' }

if ($Uninstall) {
  if (Test-Path -LiteralPath $installedDll) {
    $process = Start-Process -FilePath $regsvr32 -ArgumentList ('/s /u "{0}"' -f $installedDll) -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "GY unregister failed. regsvr32 returned $($process.ExitCode)." }
  }
  if (Test-Path -LiteralPath $legacyUserClsid) { Remove-Item -LiteralPath $legacyUserClsid -Recurse -Force }
  if (Test-Path -LiteralPath $installRoot) {
    try { Remove-Item -LiteralPath $installRoot -Recurse -Force }
    catch [System.UnauthorizedAccessException] { Write-Warning 'GY files are still loaded. They will be removed after you close applications or sign out.' }
  }
  exit 0
}

$build = Join-Path $PSScriptRoot 'build'
cmake -S $PSScriptRoot -B $build -G 'Visual Studio 17 2022' -A x64
cmake --build $build --config Release
$releaseDirectory = Join-Path $build 'bin\Release'
$builtDll = Join-Path $releaseDirectory 'GyIme.dll'
$builtRimeDll = Join-Path $releaseDirectory 'rime.dll'
$builtRimeData = Join-Path $releaseDirectory 'rime-data'
if (-not (Test-Path -LiteralPath $builtDll)) { throw 'GyIme.dll was not produced by the build.' }
if (-not (Test-Path -LiteralPath $builtRimeDll)) { throw 'rime.dll was not produced by the build.' }
if (-not (Test-Path -LiteralPath (Join-Path $builtRimeData 'shared\build\luna_pinyin.table.bin'))) { throw 'The packaged Rime dictionary was not produced by the build.' }

$installedRimeDll = Join-Path $installRoot 'rime.dll'
$installedRimeData = Join-Path $installRoot 'rime-data'
New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
if (Test-Path -LiteralPath $legacyUserClsid) { Remove-Item -LiteralPath $legacyUserClsid -Recurse -Force }
Copy-Item -LiteralPath $builtDll -Destination $installedDll -Force
Copy-Item -LiteralPath $builtRimeDll -Destination $installedRimeDll -Force
if (Test-Path -LiteralPath $installedRimeData) { Remove-Item -LiteralPath $installedRimeData -Recurse -Force }
Copy-Item -LiteralPath $builtRimeData -Destination $installedRimeData -Recurse -Force
$process = Start-Process -FilePath $regsvr32 -ArgumentList ('/s "{0}"' -f $installedDll) -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "GY registration failed. regsvr32 returned $($process.ExitCode)." }
