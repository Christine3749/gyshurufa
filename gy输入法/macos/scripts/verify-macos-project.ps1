[CmdletBinding()]
param(
  [string]$MacRoot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($MacRoot)) {
  $MacRoot = Split-Path -Parent $PSScriptRoot
}

$required = @(
  'GYInput/Sources/GYInputController.m',
  'GYInput/Sources/GYRimeBridge.mm',
  'GYInput/Sources/GYInputMode.h',
  'GYInput/Sources/GYSettingsStore.m',
  'GYInput/Sources/GYPreferencesController.m',
  'scripts/bootstrap-rime-arm64.sh',
  'scripts/build-macos.sh',
  'scripts/package-release.sh',
  'scripts/publish-r2.sh',
  'scripts/smoke-test-macos.sh'
)
foreach ($relative in $required) {
  $path = Join-Path $MacRoot $relative
  if (-not (Test-Path -LiteralPath $path)) { throw "Required macOS delivery file missing: $relative" }
}

$controller = Get-Content -LiteralPath (Join-Path $MacRoot 'GYInput/Sources/GYInputController.m') -Raw
$bridge = Get-Content -LiteralPath (Join-Path $MacRoot 'GYInput/Sources/GYRimeBridge.mm') -Raw
$plist = Get-Content -LiteralPath (Join-Path $MacRoot 'GYInput/Resources/Info.plist') -Raw
$build = Get-Content -LiteralPath (Join-Path $MacRoot 'scripts/build-macos.sh') -Raw
$package = Get-Content -LiteralPath (Join-Path $MacRoot 'scripts/package-release.sh') -Raw
$publish = Get-Content -LiteralPath (Join-Path $MacRoot 'scripts/publish-r2.sh') -Raw

foreach ($needle in @('GYInputModeTraditional', 'GYInputModeEnglish', 'kVK_Return', 'kVK_PageUp', 'kVK_PageDown', 'GYInputModeIsChinese', 'commitDisplayedCandidateAtIndex', 'showPreferences:')) {
  if (-not $controller.Contains($needle)) { throw "Controller regression: missing $needle" }
}
if ($controller -notmatch '(?s)- \(NSMenu \*\)menu \{\s+NSMenu \*menu') { throw 'Controller regression: malformed input-method menu.' }
if ($controller -match '(?s)- \(NSMenu \*\)menu \{\s*- \(') { throw 'Controller regression: a method was nested inside the menu.' }
foreach ($needle in @('staged arm64 librime SDK', 'change_page', 'free_commit', '#error')) {
  if (-not $bridge.Contains($needle)) { throw "Rime bridge regression: missing $needle" }
}
foreach ($needle in @('$(MARKETING_VERSION)', '$(CURRENT_PROJECT_VERSION)')) {
  if (-not $plist.Contains($needle)) { throw "Mac bundle must receive version from the unified release build: missing $needle" }
}
foreach ($needle in @('GY_RELEASE_VERSION', 'MARKETING_VERSION', 'CURRENT_PROJECT_VERSION')) {
  if (-not $build.Contains($needle)) { throw "Mac build does not consume the canonical release version: missing $needle" }
}
if ($package.Contains('rm -rf "$release_dir"')) { throw 'Mac package script must never overwrite an existing versioned release directory.' }
if ($publish.Contains('wrangler deploy')) { throw 'Mac upload script must not deploy the Worker or switch public latest.' }
if (-not $publish.Contains('releases/$version/macos/$file')) { throw 'Mac upload path must be immutable and platform-scoped.' }

Write-Host 'PASS: macOS project release contract, input modes, Rime paging, and no-overwrite upload rules are present.'
Write-Host 'NOTE: Apple Silicon build, signing, notarization, and app compatibility still require verification on a Mac.'
