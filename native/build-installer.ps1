param(
  [string]$Version
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ReleaseManifest.psm1') -Force
$manifest = Get-GYReleaseManifest
$Version = Assert-GYReleaseVersion -Manifest $manifest -RequestedVersion $Version

$isccCandidates = @(
  (Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source),
  'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
  'C:\Program Files\Inno Setup 6\ISCC.exe',
  (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
$isccCandidates = @($isccCandidates)
if (-not $isccCandidates) {
  throw 'Inno Setup 6 is required to build the EXE installer. Install it, then run this script again.'
}

$payloadDirectory = Join-Path $PSScriptRoot "release\GYInput-$Version\payload"
$releaseDll = Join-Path $payloadDirectory "GyIme-$Version.dll"
$releaseHost = Join-Path $payloadDirectory "GyImeHost-$Version.exe"
$releaseHealth = Join-Path $payloadDirectory "GyImeHealth-$Version.exe"
if (-not (Test-Path -LiteralPath $releaseDll) -or -not (Test-Path -LiteralPath $releaseHost) -or -not (Test-Path -LiteralPath $releaseHealth)) {
  throw "Release payload (DLL, Host, or Health Check) is missing. Run native\package.ps1 for version $Version first."
}

& $isccCandidates[0] "/DMyAppVersion=$Version" "/DMyTsfVersion=$Version" (Join-Path $PSScriptRoot 'installer\GYInput.iss')
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }
Write-Host "EXE installer created: $(Join-Path $PSScriptRoot "release\GYInputSetup-$Version.exe")"