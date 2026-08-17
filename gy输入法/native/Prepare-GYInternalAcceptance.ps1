[CmdletBinding()]
param(
  [string]$OutputRoot = ''
)

# This is intentionally not a release packager.  It builds a production-mode
# payload solely for a controlled local upgrade/rollback rehearsal.  It never
# writes under release/, never creates EXE/ZIP output, and cannot publish.
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $PSScriptRoot 'internal-acceptance'
}
Import-Module (Join-Path $PSScriptRoot 'ReleaseManifest.psm1') -Force
$manifest = Get-GYReleaseManifest
$version = Assert-GYReleaseVersion -Manifest $manifest -RequestedVersion ''
if ([string]$manifest.windows.state -ne 'draft') {
  throw 'Internal acceptance is only valid for a fresh draft. Do not rehearse a candidate or published release on this machine.'
}

$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$packageRoot = Join-Path $OutputRoot ("GYInput-InternalAcceptance-" + $version)
if (Test-Path -LiteralPath $packageRoot) {
  throw "Internal acceptance output already exists: $packageRoot. Inspect or archive it; never overwrite an acceptance record."
}

# This is deliberately a distinct cache from the regular safety build. The latter
# enables GY_TESTING for smoke tests; a real TSF rehearsal must use exactly
# the production Host and DLL configuration.
$build = Join-Path $PSScriptRoot 'build-internal-acceptance'
cmake -S $PSScriptRoot -B $build -G 'Visual Studio 17 2022' -A x64 `
  '-DGY_BUILD_HOST_SMOKE=OFF' '-DGY_BUILD_CANDIDATE_LAB=OFF' '-DGY_IME_TRACE=OFF' '-DGY_REGISTRATION_TRACE=OFF'
if ($LASTEXITCODE -ne 0) { throw 'Production-mode internal acceptance configuration failed.' }
cmake --build $build --config Release --target GyIme GyImeHost GyImeHealth GyEnRealAppRegression --parallel 2
if ($LASTEXITCODE -ne 0) { throw 'Production-mode internal acceptance build failed.' }

$hostProject = Get-Content -LiteralPath (Join-Path $build 'GyImeHost.vcxproj') -Raw
if ($hostProject.Contains('GY_TESTING')) {
  throw 'Internal acceptance Host project contains GY_TESTING. Refusing to rehearse a test-mode Host as a production candidate.'
}

$binaryRoot = Join-Path $build 'bin\Release'
foreach ($name in 'GyIme.dll', 'GyImeHost.exe', 'GyImeHealth.exe', 'GyEnRealAppRegression.exe', 'rime.dll') {
  if (-not (Test-Path -LiteralPath (Join-Path $binaryRoot $name) -PathType Leaf)) {
    throw "Internal acceptance binary is missing: $name"
  }
}
foreach ($name in 'GyIme.dll', 'GyImeHost.exe', 'GyImeHealth.exe') {
  $actual = [string](Get-Item -LiteralPath (Join-Path $binaryRoot $name)).VersionInfo.ProductVersion
  if ($actual -ne $version) { throw "Internal acceptance binary version mismatch: $name is $actual, expected $version." }
}
if (-not (Test-Path -LiteralPath (Join-Path $binaryRoot 'rime-data\shared\build\luna_pinyin.table.bin') -PathType Leaf)) {
  throw 'Internal acceptance offline Rime data is incomplete.'
}

$payloadRoot = Join-Path $packageRoot 'payload'
$toolsRoot = Join-Path $packageRoot 'tools'
New-Item -ItemType Directory -Path $payloadRoot, $toolsRoot, (Join-Path $packageRoot 'LICENSES') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $binaryRoot 'GyIme.dll') -Destination (Join-Path $payloadRoot "GyIme-$version.dll")
Copy-Item -LiteralPath (Join-Path $binaryRoot 'GyImeHost.exe') -Destination (Join-Path $payloadRoot "GyImeHost-$version.exe")
Copy-Item -LiteralPath (Join-Path $binaryRoot 'GyImeHealth.exe') -Destination (Join-Path $payloadRoot "GyImeHealth-$version.exe")
Copy-Item -LiteralPath (Join-Path $binaryRoot 'rime.dll') -Destination (Join-Path $payloadRoot 'rime.dll')
Copy-Item -LiteralPath (Join-Path $binaryRoot 'rime-data') -Destination (Join-Path $payloadRoot 'rime-data') -Recurse
Copy-Item -LiteralPath (Join-Path $binaryRoot 'GyEnRealAppRegression.exe') -Destination (Join-Path $toolsRoot 'GyEnRealAppRegression.exe')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer\assets\gy.ico') -Destination (Join-Path $payloadRoot 'gy.ico')

$workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$notes = Join-Path $workspaceRoot "release\notes\$version.txt"
if (-not (Test-Path -LiteralPath $notes -PathType Leaf)) { throw "Internal acceptance release notes are missing: $notes" }
Copy-Item -LiteralPath $notes -Destination (Join-Path $payloadRoot 'release-notes.txt')

foreach ($name in @(
  'Install-GYInput.ps1', 'Set-GYKeyboard.ps1', 'Validate-GYInput.ps1', 'Get-GYLoadedClientState.ps1', 'Get-GYKeepHealth.ps1',
  'Rollback-GYInput.ps1', 'Repair-GYInput.ps1', 'AutoUpdate-GYInput.ps1', 'Sync-GYEnglishLexicon.ps1',
  'Finalize-GYClientReload.ps1', 'Prune-GYOldVersions.ps1', 'Migrate-GYLegacyInstallEntries.ps1',
  'Register-GYInputActivationTasks.ps1', 'GYInputTransaction.ps1'
)) {
  $source = Join-Path $PSScriptRoot "installer\$name"
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Required internal acceptance helper is missing: $source" }
  Copy-Item -LiteralPath $source -Destination (Join-Path $packageRoot $name)
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'runtime\rime\LICENSE.librime.txt') -Destination (Join-Path $packageRoot 'LICENSES\librime-BSD-3-Clause.txt')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'runtime\rime\LICENSE.rime-data.txt') -Destination (Join-Path $packageRoot 'LICENSES\rime-data-license.txt')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'runtime\rime\LICENSE.opencc.txt') -Destination (Join-Path $packageRoot 'LICENSES\opencc-Apache-2.0.txt')
Set-Content -LiteralPath (Join-Path $packageRoot 'VERSION') -Value $version -NoNewline -Encoding utf8

$hashLines = Get-ChildItem -LiteralPath $payloadRoot -File -Recurse | ForEach-Object {
  $relative = $_.FullName.Substring($payloadRoot.Length + 1)
  "{0}  {1}" -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, $relative
}
Set-Content -LiteralPath (Join-Path $payloadRoot 'SHA256SUMS.txt') -Value $hashLines -Encoding utf8

$record = [ordered]@{
  schemaVersion = 1
  purpose = 'internal-upgrade-rollback-acceptance-only'
  version = $version
  releaseId = [string]$manifest.releaseId
  releaseState = [string]$manifest.windows.state
  builtAtUtc = [DateTime]::UtcNow.ToString('o')
  publicReleaseArtifact = $false
  packageRoot = $packageRoot
}
$record | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $packageRoot 'internal-acceptance.json') -Encoding utf8
@"
INTERNAL ACCEPTANCE ONLY — NOT A RELEASE ARTIFACT

Version: $version
Purpose: one explicitly authorized local 0.10.95 -> $version -> 0.10.95 rehearsal.

This directory must never be copied to release/, zipped, signed, uploaded,
or used by automatic update. It has no release manifest and no installer EXE.
"@ | Set-Content -LiteralPath (Join-Path $packageRoot 'INTERNAL-ACCEPTANCE-NOT-FOR-DISTRIBUTION.txt') -Encoding utf8

Write-Host "Production-mode internal acceptance root prepared: $packageRoot" -ForegroundColor Yellow
