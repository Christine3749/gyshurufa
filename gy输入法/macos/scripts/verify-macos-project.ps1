[CmdletBinding()]
param(
  [string]$MacRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$required = @(
  'GYInput/Sources/GYInputController.m',
  'GYInput/Sources/GYRimeBridge.mm',
  'GYInput/Sources/GYInputMode.h',
  'GYInput/Sources/GYSettingsStore.m',
  'scripts/bootstrap-rime-arm64.sh',
  'scripts/build-macos.sh',
  'scripts/package-release.sh'
)
foreach ($relative in $required) {
  $path = Join-Path $MacRoot $relative
  if (-not (Test-Path -LiteralPath $path)) { throw "Required macOS delivery file missing: $relative" }
}

$controller = Get-Content -LiteralPath (Join-Path $MacRoot 'GYInput/Sources/GYInputController.m') -Raw
$bridge = Get-Content -LiteralPath (Join-Path $MacRoot 'GYInput/Sources/GYRimeBridge.mm') -Raw
$plist = Get-Content -LiteralPath (Join-Path $MacRoot 'GYInput/Resources/Info.plist') -Raw
foreach ($needle in @('GYInputModeTraditional', 'GYInputModeEnglish', 'kVK_Return', 'kVK_PageUp', 'kVK_PageDown', 'GYInputModeIsChinese')) {
  if (-not $controller.Contains($needle)) { throw "Controller regression: missing $needle" }
}
foreach ($needle in @('staged arm64 librime SDK', 'change_page', 'free_commit', '#error')) {
  if (-not $bridge.Contains($needle)) { throw "Rime bridge regression: missing $needle" }
}
if ($plist -notmatch '<string>0\.9\.15</string>') { throw 'Mac bundle version must match the Windows 0.9.15 release baseline.' }
Write-Host 'PASS: macOS project layout, input modes, Rime paging, and release scripts are present.'
Write-Host 'NOTE: Apple Silicon build, signing, notarization, and app compatibility still require a Mac.'
