param(
  [string]$InstallerPath = (Join-Path $PSScriptRoot 'Install-GYInput.ps1'),
  [string]$InnoPath = (Join-Path $PSScriptRoot 'GYInput.iss'),
  [string]$RollbackPath = (Join-Path $PSScriptRoot 'Rollback-GYInput.ps1')
)

$ErrorActionPreference = 'Stop'
function Assert-Contains([string]$Source, [string]$Needle, [string]$Message) {
  if (-not $Source.Contains($Needle)) { throw $Message }
}
function Assert-ScriptParses([string]$Path) {
  $errors = $null
  $content = Get-Content -LiteralPath $Path -Raw
  $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)
  if ($errors -and $errors.Count) { throw ("PowerShell syntax error in {0}: {1}" -f $Path, $errors[0].Message) }
  return $content
}

$installer = Assert-ScriptParses $InstallerPath
$rollback = Assert-ScriptParses $RollbackPath
$signing = Assert-ScriptParses (Join-Path $PSScriptRoot 'Sign-GYRelease.ps1')
$verification = Assert-ScriptParses (Join-Path $PSScriptRoot 'Verify-GYRelease.ps1')
$packaging = Assert-ScriptParses (Join-Path $PSScriptRoot '..\package.ps1')
$finalize = Assert-ScriptParses (Join-Path $PSScriptRoot '..\Finalize-GYRelease.ps1')
$inno = Get-Content -LiteralPath $InnoPath -Raw
Assert-Contains $installer '[switch]$Rollback' 'ZIP installer does not expose rollback.'
Assert-Contains $installer 'Test-ManagedGyPath' 'ZIP installer rollback does not verify managed paths.'
Assert-Contains $installer 'Start-Process -FilePath $health' 'ZIP installer rollback does not health-check its target.'
Assert-Contains $installer 'Save-PreviousGyState' 'ZIP installer does not preserve an upgrade rollback point.'
Assert-Contains $installer 'activationState = $activationState' 'ZIP installer does not record core activation state.'
Assert-Contains $installer 'Test-ThisReleaseActive' 'ZIP installer does not verify that registry activation matches the staged release.'
Assert-Contains $installer 'Write-GyStateAtomically' 'ZIP installer does not atomically persist activation state.'
Assert-Contains $rollback 'Rollback refused: Host is outside the managed GYInput directory.' 'Standalone rollback does not protect its Host path.'
Assert-Contains $rollback 'Previous version health check failed' 'Standalone rollback does not health-check its target.'
Assert-Contains $inno 'Rollback-GYInput.ps1' 'EXE installer does not ship rollback support.'
Assert-Contains $inno 'SaveCapturedPreviousGyState' 'EXE installer does not preserve an upgrade rollback point.'
Assert-Contains $inno 'CoreConnectorIsNew' 'EXE installer does not distinguish a Host-only update from a core update.'
Assert-Contains $inno 'VerifyActivatedRelease' 'EXE installer does not verify the activated DLL / Host version.'
Assert-Contains $inno 'RestoreCapturedPreviousGyState' 'EXE installer cannot safely restore the previous activation state.'
Assert-Contains $verification 'Get-GYReleaseManifest' 'Release verifier does not use the canonical release manifest.'
Assert-Contains $verification 'Package release.json matches Windows package/core/host' 'Release verifier does not validate package version consistency.'
Assert-Contains $signing 'Set-AuthenticodeSignature' 'Signing workflow does not sign release binaries.'
Assert-Contains $signing 'Verify-GYRelease.ps1' 'Signing workflow does not force final verification.'
Assert-Contains $verification 'Get-AuthenticodeSignature' 'Release verifier does not inspect Authenticode status.'
Assert-Contains $verification '[switch]$RequireSignature' 'Release verifier cannot enforce public-Beta signing.'
Assert-Contains $verification 'Installer SHA-256 and byte size match canonical release.json.' 'Release verifier does not bind the installer to the canonical hash and byte size.'
if ($packaging.Contains('Compress-Archive')) { throw 'Package preparation must not create a ZIP before final release metadata is verified.' }
Assert-Contains $finalize 'Copy-Item -LiteralPath $manifestPath -Destination $packageManifest -Force' 'Finalize must embed the final canonical release.json before creating the ZIP.'
$manifestModule = Assert-ScriptParses (Join-Path $PSScriptRoot '..\ReleaseManifest.psm1')
Assert-Contains $manifestModule 'Windows setupFile does not match its version.' 'Release manifest does not enforce versioned installer naming.'
Assert-Contains $manifestModule 'PENDING-PACKAGE-VERIFICATION' 'Release manifest does not distinguish an unfinished draft from a publishable artifact.'
$publish = Assert-ScriptParses (Join-Path $PSScriptRoot '..\Publish-GYRelease.ps1')
Assert-Contains $publish 'Atomically advance verified cross-platform latest pointer' 'Publish workflow does not atomically switch the R2 latest pointer last.'
Assert-Contains $publish '-RequireSignature:$requireSignature' 'Publish workflow does not require signatures for stable releases.'
$worker = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\release-service\src\release-worker-v2.js') -Raw
Assert-Contains $worker 'releases/latest.json' 'Download worker is not driven by R2 latest.json.'
if ($worker.Contains('0.4.2')) { throw 'Download worker still contains a hard-coded legacy release version.' }
$candidateHeader = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\CandidateWindow.h') -Raw
Assert-Contains $candidateHeader 'kCandidatesPerPage = 5' 'Candidate contract changed: default row must have five candidates.'
Assert-Contains $candidateHeader 'kExpandedColumns = gy::candidate_layout::ExpandedColumns()' 'Candidate contract changed: expanded grid must have five columns.'
Assert-Contains $candidateHeader 'kExpandedMaxRows = gy::candidate_layout::ExpandedRows(25)' 'Candidate contract changed: expanded grid must have at most five rows.'
$candidateLayout = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\CandidateLayout.h') -Raw
Assert-Contains $candidateLayout 'constexpr unsigned ExpandedColumns() noexcept { return 5; }' 'Candidate contract changed: expanded grid must have exactly five columns.'
Assert-Contains $candidateLayout 'constexpr unsigned ExpandedRows(unsigned candidate_count,' 'Candidate contract changed: expanded grid row calculation is missing.'
$candidateWindow = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\CandidateWindow.cpp') -Raw
Assert-Contains $candidateWindow 'Do not clamp a normal four-character candidate back into an ellipsis.' 'Candidate renderer must preserve complete four-character words.'
Assert-Contains $candidateWindow 'candidate_font, false' 'Candidate renderer must not ellipsize candidate text.'
$ime = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\GyIme.cpp') -Raw
Assert-Contains $ime 'if (key == VK_DOWN)' 'Candidate contract changed: Down must expand or page candidates.'
Assert-Contains $ime 'expanded_candidates_ = true' 'Candidate contract changed: first Down must expand the candidate grid.'
Write-Host 'Installer upgrade/rollback/signing smoke: PASS'
