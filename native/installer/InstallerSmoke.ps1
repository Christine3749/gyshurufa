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
$inno = Get-Content -LiteralPath $InnoPath -Raw
Assert-Contains $installer '[switch]$Rollback' 'ZIP installer does not expose rollback.'
Assert-Contains $installer 'Test-ManagedGyPath' 'ZIP installer rollback does not verify managed paths.'
Assert-Contains $installer 'Start-Process -FilePath $health' 'ZIP installer rollback does not health-check its target.'
Assert-Contains $installer 'Save-PreviousGyState' 'ZIP installer does not preserve an upgrade rollback point.'
Assert-Contains $rollback 'Rollback refused: Host is outside the managed GYInput directory.' 'Standalone rollback does not protect its Host path.'
Assert-Contains $rollback 'Previous version health check failed' 'Standalone rollback does not health-check its target.'
Assert-Contains $inno 'Rollback-GYInput.ps1' 'EXE installer does not ship rollback support.'
Assert-Contains $inno 'SaveCapturedPreviousGyState' 'EXE installer does not preserve an upgrade rollback point.'
Assert-Contains $inno 'CoreConnectorIsNew' 'EXE installer does not distinguish a Host-only update from a core update.'
Assert-Contains $inno 'VerifyActivatedRelease' 'EXE installer does not verify the activated DLL / Host version.'
Assert-Contains $inno 'RestoreCapturedPreviousGyState' 'EXE installer cannot safely restore the previous activation state.'
Assert-Contains $verification 'Get-GYReleaseManifest' 'Release verifier does not use the canonical release manifest.'
Assert-Contains $verification 'Package release.json matches package/core/host' 'Release verifier does not validate package version consistency.'
Assert-Contains $signing 'Set-AuthenticodeSignature' 'Signing workflow does not sign release binaries.'
Assert-Contains $signing 'Verify-GYRelease.ps1' 'Signing workflow does not force final verification.'
Assert-Contains $verification 'Get-AuthenticodeSignature' 'Release verifier does not inspect Authenticode status.'
Assert-Contains $verification '[switch]$RequireSignature' 'Release verifier cannot enforce public-Beta signing.'
Write-Host 'Installer upgrade/rollback/signing smoke: PASS'