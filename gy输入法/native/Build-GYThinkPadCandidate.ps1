[CmdletBinding()]
param(
  [string]$Version = '',
  [string]$OutputRoot = '',
  [switch]$EnableTsfTrace
)

# This creates an unsigned, production-mode, version-pinned package for one
# explicitly authorized private ThinkPad acceptance. It is deliberately not a
# substitute for the approval-gated public release pipeline.
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $PSScriptRoot 'release' }
Import-Module (Join-Path $PSScriptRoot 'ReleaseManifest.psm1') -Force
$manifest = Get-GYReleaseManifest
$Version = Assert-GYReleaseVersion -Manifest $manifest -RequestedVersion $Version
if ([string]$manifest.windows.state -ne 'draft' -or [string]$manifest.channel -ne 'candidate') {
  throw 'ThinkPad candidate build requires a fresh candidate draft.'
}

$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$packageRoot = Join-Path $OutputRoot "GYInput-$Version"
$setup = Join-Path $OutputRoot "GYInputSetup-$Version.exe"
$zip = Join-Path $OutputRoot "GYInput-$Version.zip"
foreach ($path in $packageRoot, $setup, $zip) {
  if (Test-Path -LiteralPath $path) { throw "Refusing to overwrite an existing ThinkPad candidate artifact: $path" }
}

$build = Join-Path $PSScriptRoot "build-thinkpad-$Version"
$traceOption = if ($EnableTsfTrace) { '-DGY_IME_TRACE=ON' } else { '-DGY_IME_TRACE=OFF' }
cmake -S $PSScriptRoot -B $build -G 'Visual Studio 17 2022' -A x64 `
  "-DGY_VERSION=$Version" '-DGY_BUILD_HOST_SMOKE=OFF' '-DGY_BUILD_CANDIDATE_LAB=OFF' `
  $traceOption '-DGY_REGISTRATION_TRACE=OFF'
if ($LASTEXITCODE -ne 0) { throw 'ThinkPad production-mode configuration failed.' }
cmake --build $build --config Release --target GyIme GyImeHost GyImeHealth --parallel 2
if ($LASTEXITCODE -ne 0) { throw 'ThinkPad production-mode build failed.' }

$hostProject = Get-Content -LiteralPath (Join-Path $build 'GyImeHost.vcxproj') -Raw
if ($hostProject.Contains('GY_TESTING')) { throw 'ThinkPad candidate Host contains GY_TESTING.' }
$binaryRoot = Join-Path $build 'bin\Release'
foreach ($name in 'GyIme.dll', 'GyImeHost.exe', 'GyImeHealth.exe') {
  $path = Join-Path $binaryRoot $name
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "ThinkPad candidate binary is missing: $name" }
  if ([string](Get-Item -LiteralPath $path).VersionInfo.ProductVersion -ne $Version) {
    throw "ThinkPad candidate version metadata is wrong: $name"
  }
}

$payloadRoot = Join-Path $packageRoot 'payload'
$licensesRoot = Join-Path $packageRoot 'LICENSES'
New-Item -ItemType Directory -Path $payloadRoot, $licensesRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $binaryRoot 'GyIme.dll') -Destination (Join-Path $payloadRoot "GyIme-$Version.dll")
Copy-Item -LiteralPath (Join-Path $binaryRoot 'GyImeHost.exe') -Destination (Join-Path $payloadRoot "GyImeHost-$Version.exe")
Copy-Item -LiteralPath (Join-Path $binaryRoot 'GyImeHealth.exe') -Destination (Join-Path $payloadRoot "GyImeHealth-$Version.exe")
Copy-Item -LiteralPath (Join-Path $binaryRoot 'rime.dll') -Destination (Join-Path $payloadRoot 'rime.dll')
Copy-Item -LiteralPath (Join-Path $binaryRoot 'rime-data') -Destination (Join-Path $payloadRoot 'rime-data') -Recurse
Copy-Item -LiteralPath (Join-Path $binaryRoot 'english-lexicon') -Destination (Join-Path $payloadRoot 'english-lexicon') -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer\assets\gy.ico') -Destination (Join-Path $payloadRoot 'gy.ico')

$workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$notes = Join-Path $workspaceRoot "release\notes\$Version.txt"
if (-not (Test-Path -LiteralPath $notes -PathType Leaf)) { throw "ThinkPad candidate notes are missing: $notes" }
Copy-Item -LiteralPath $notes -Destination (Join-Path $payloadRoot 'release-notes.txt')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'runtime\rime\LICENSE.librime.txt') -Destination (Join-Path $licensesRoot 'librime-BSD-3-Clause.txt')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'runtime\rime\LICENSE.rime-data.txt') -Destination (Join-Path $licensesRoot 'rime-data-license.txt')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'runtime\rime\LICENSE.opencc.txt') -Destination (Join-Path $licensesRoot 'opencc-Apache-2.0.txt')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'runtime\english\LICENSE.frequency-words.txt') -Destination (Join-Path $licensesRoot 'english-frequency-words-CC-BY-SA-4.0.txt')

foreach ($name in @(
  'Install-GYInput.ps1', 'Set-GYKeyboard.ps1', 'Validate-GYInput.ps1', 'Get-GYLoadedClientState.ps1',
  'Get-GYKeepHealth.ps1', 'Rollback-GYInput.ps1', 'Repair-GYInput.ps1', 'AutoUpdate-GYInput.ps1',
  'Sync-GYEnglishLexicon.ps1', 'Finalize-GYClientReload.ps1', 'Prune-GYOldVersions.ps1',
  'Migrate-GYLegacyInstallEntries.ps1', 'Register-GYInputActivationTasks.ps1',
  'Recover-GYIncompleteRegistration.ps1', 'GYInputTransaction.ps1'
)) {
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot "installer\$name") -Destination (Join-Path $packageRoot $name)
}
Set-Content -LiteralPath (Join-Path $packageRoot 'VERSION') -Value $Version -NoNewline -Encoding utf8
$hashLines = Get-ChildItem -LiteralPath $payloadRoot -File -Recurse | ForEach-Object {
  $relative = $_.FullName.Substring($payloadRoot.Length + 1)
  "{0}  {1}" -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, $relative
}
Set-Content -LiteralPath (Join-Path $payloadRoot 'SHA256SUMS.txt') -Value $hashLines -Encoding utf8

$iscc = @(
  (Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source),
  'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
  'C:\Program Files\Inno Setup 6\ISCC.exe',
  (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 is required to build the ThinkPad candidate.' }
& $iscc "/DMyAppVersion=$Version" "/DMyTsfVersion=$Version" '/DMyThinkPadCandidate=1' (Join-Path $PSScriptRoot 'installer\GYInput.iss')
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $setup -PathType Leaf)) { throw 'ThinkPad candidate installer build failed.' }

$setupHash = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash
$setupBytes = (Get-Item -LiteralPath $setup).Length
$candidateDate = [DateTime]::UtcNow.ToString('yyyy.MM.dd')
$candidateManifest = [ordered]@{
  schemaVersion = 2
  releaseId = "gy-$candidateDate-windows-$Version-thinkpad-test"
  channel = 'candidate'
  windows = [ordered]@{
    version = $Version; coreVersion = $Version; hostVersion = $Version; architecture = 'x64'
    setupFile = "GYInputSetup-$Version.exe"; zipFile = "GYInput-$Version.zip"
    sha256 = $setupHash; bytes = $setupBytes; state = 'candidate'
  }
  macos = [ordered]@{ version = '2.0.0'; architecture = 'arm64'; state = 'verification-required' }
  publishedAtUtc = [DateTime]::UtcNow.ToString('o')
  internalTest = [ordered]@{
    audience = 'Ethan private ThinkPad'
    signed = $false
    tsfLifecycleTrace = [bool]$EnableTsfTrace
    realApplications = 'pending'
    pointerPolicy = 'version-pinned-only'
  }
}
$candidateManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $packageRoot 'release.json') -Encoding utf8
Compress-Archive -LiteralPath $packageRoot -DestinationPath $zip -CompressionLevel Optimal
Set-Content -LiteralPath "$setup.sha256" -Value "$setupHash  GYInputSetup-$Version.exe" -NoNewline -Encoding ascii

Write-Host "ThinkPad candidate built: $setup" -ForegroundColor Green
Write-Host "SHA-256: $setupHash" -ForegroundColor Green
