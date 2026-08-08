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
$repair = Assert-ScriptParses (Join-Path $PSScriptRoot 'Repair-GYInput.ps1')
$prune = Assert-ScriptParses (Join-Path $PSScriptRoot 'Prune-GYOldVersions.ps1')
$clientFinalizer = Assert-ScriptParses (Join-Path $PSScriptRoot 'Finalize-GYClientReload.ps1')
$releaseState = Assert-ScriptParses (Join-Path $PSScriptRoot 'Get-GYReleaseState.ps1')
$transaction = Assert-ScriptParses (Join-Path $PSScriptRoot 'GYInputTransaction.ps1')
$taskRegistrar = Assert-ScriptParses (Join-Path $PSScriptRoot 'Register-GYInputActivationTasks.ps1')
$validator = Assert-ScriptParses (Join-Path $PSScriptRoot 'Validate-GYInput.ps1')
$keyboard = Assert-ScriptParses (Join-Path $PSScriptRoot 'Set-GYKeyboard.ps1')
$e2e = Assert-ScriptParses (Join-Path $PSScriptRoot 'Test-GYInputUpgradeRollback.ps1')
$settingsSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\SettingsWindow.cpp') -Raw
Assert-Contains $transaction 'Global\GYInputFinalizePending' 'Shared transaction helper does not define the canonical mutex name.'
Assert-Contains $installer 'Invoke-WithGYInputTransaction' 'ZIP installer does not serialize its full elevated transaction.'
Assert-Contains $installer 'if (-not $isAdmin)' 'ZIP installer does not avoid redundant elevation in an existing Administrator PowerShell.'
Assert-Contains $rollback 'Invoke-WithGYInputTransaction' 'Standalone rollback does not serialize its activation transaction.'
Assert-Contains $rollback 'if (-not $Elevated -and -not $isAdmin)' 'Standalone rollback opens a redundant UAC process even when it is already elevated.'
Assert-Contains $repair 'Invoke-WithGYInputTransaction' 'One-click repair does not serialize its activation transaction.'
Assert-Contains $repair 'Complete-PendingActivation' 'One-click repair cannot complete a pending core activation.'
Assert-Contains $repair 'Test-ManagedGyPath' 'One-click repair does not constrain registry targets to managed paths.'
Assert-Contains $repair 'Start-Process -FilePath (Get-X64RegSvr32)' 'One-click repair does not re-register the verified TSF DLL.'
Assert-Contains $repair 'Remove-StaleTransientHelpers' 'One-click repair does not clean expired staged helper files.'
Assert-Contains $repair 'Prune-GYOldVersions.ps1' 'One-click repair does not invoke the audited old-version cleaner.'
Assert-Contains $repair 'Write-RecoveryReport' 'One-click repair does not persist a durable recovery result.'
Assert-Contains $repair '部分旧版本清理将于下次整备继续' 'One-click repair treats non-critical cleanup as a hard recovery failure.'
if ($repair -match '(?m)^\s*return\s+if\s*\(') { throw 'One-click repair uses PowerShell return-if syntax that fails at runtime.' }
Assert-Contains $clientFinalizer 'Pending GY activation rollback state is missing or unmanaged.' 'Finalizer does not validate its rollback paths.'
Assert-Contains $clientFinalizer 'requiresClientReload = $false' 'Finalizer does not close the pending reload state.'
Assert-Contains $clientFinalizer 'GYInputTransaction.ps1' 'Finalizer does not load the shared transaction helper.'
Assert-Contains $clientFinalizer '$LockAlreadyHeld' 'Finalizer cannot be safely invoked by a lock-owning installer transaction.'
Assert-Contains $clientFinalizer 'Start-TransientHelperCleanup' 'Finalizer does not clean one-shot helper files after successful activation.'
Assert-Contains $clientFinalizer '$pendingActivationPath' 'Finalizer cleanup does not protect a newly staged activation transaction.'
Assert-Contains $clientFinalizer 'Previous GY rollback target' 'Finalizer does not verify the prior healthy target before switching registration.'
Assert-Contains $clientFinalizer 'Assert-RegisteredGyState' 'Finalizer does not read back both DLL and Host registration.'
Assert-Contains $clientFinalizer 'Write-VerifiedActiveState' 'Finalizer does not persist only a registry-verified active state.'
Assert-Contains $clientFinalizer '$registrationChanged' 'Finalizer may restore a prior registration even when it did not change the registry.'
$finalizerWaitCount = [regex]::Matches($clientFinalizer, '\$mutex\.WaitOne\(0\)').Count
Assert-Contains $taskRegistrar 'Wait-GYInputScheduledTask' 'Activation task registrar does not read back task persistence.'
Assert-Contains $taskRegistrar "'ONSTART'" 'Activation task registrar does not create an ONSTART task.'
Assert-Contains $taskRegistrar "'ONLOGON'" 'Activation task registrar does not create an ONLOGON task.'
Assert-Contains $taskRegistrar 'Remove-StaleTransientHelpers' 'Task registrar does not clean unneeded one-shot helper files.'
if ($finalizerWaitCount -ne 2) { throw "Finalizer must acquire the shared mutex for activation and guarded cleanup; found $finalizerWaitCount WaitOne calls." }
if ($installer -match '\$host\b' -or $rollback -match '\$host\b') { throw 'Installer scripts must not assign PowerShell automatic variable Host.' }
Assert-Contains $prune 'Get-GYOldSiblingPath' 'Prune script does not preserve occupied paths with deterministic old names.'
Assert-Contains $prune '.old.' 'Prune script does not use .old.N recovery names.'
Assert-Contains $prune 'versions\.old\.\d+' 'Prune script does not retry abandoned versions.old.N directories.'
Assert-Contains $prune 'Preserve-GYLockedFiles' 'Prune script does not probe locked DLLs before delete.'
Assert-Contains $prune 'Copy-Item -LiteralPath $file.FullName -Destination $fileSibling' 'Prune script does not preserve an occupied DLL payload.'
if ($prune.Contains('.trash')) { throw 'Prune script must not use ambiguous .trash names.' }
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
Assert-Contains $installer "activationState = 'pending'" 'ZIP installer does not record explicit pending state.'
Assert-Contains $installer "Write-GyActivationState 'staged'" 'ZIP installer does not record staged state before pending.'
Assert-Contains $validator 'Get-GyCoreVersionFromPath' 'Post-install validation does not derive the registered TSF version.'
Assert-Contains $validator 'Host Logo 存在' 'Post-install validation does not verify the Host Logo.'
Assert-Contains $validator 'TSF Logo 存在' 'Post-install validation does not verify the TSF Logo.'
Assert-Contains $rollback "action = 'rollback'" 'Rollback does not persist an explicit recovery action.'
Assert-Contains $settingsSource 'ReadRegisteredDllVersion' 'Settings page does not read the actual registered TSF version.'
Assert-Contains $settingsSource 'registered_core_version_' 'Settings page does not retain the actual TSF version.'
Assert-Contains $settingsSource 'versions_consistent_' 'Settings page does not display real Host/DLL/TSF consistency.'
Assert-Contains $settingsSource 'BeginUpdateRepair' 'Settings update page does not provide a repair action.'
Assert-Contains $settingsSource 'Repair-GYInput.ps1' 'Settings repair action does not use the installed maintenance script.'
Assert-Contains $settingsSource 'ShellExecuteExW' 'Settings repair action does not request administrator elevation.'
Assert-Contains $settingsSource 'BeginUpdateRollback' 'Settings update page does not provide a one-click rollback action.'
Assert-Contains $settingsSource 'Rollback-GYInput.ps1' 'Settings rollback action does not use the installed rollback script.'
Assert-Contains $settingsSource 'InstalledRollbackVersion' 'Settings update page cannot display a rollback target.'
Assert-Contains $installer 'Test-ThisReleaseActive' 'ZIP installer does not verify that registry activation matches the staged release.'
Assert-Contains $installer 'Write-GyStateAtomically' 'ZIP installer does not atomically persist activation state.'
Assert-Contains $installer 'release-notes.txt' 'ZIP installer does not install version-specific release notes.'
Assert-Contains $installer 'Invoke-InstalledValidation' 'ZIP installer does not run post-install validation.'
Assert-Contains $installer 'Should-PreserveExistingPendingHelpers' 'ZIP installer may downgrade shared activation helpers from a newer active release.'
Assert-Contains $installer 'A failed task registration must not leave a false pending marker behind.' 'ZIP installer does not clean a failed pending-task registration transaction.'
Assert-Contains $installer 'Register-GYInputActivationTasks.ps1' 'ZIP installer does not use the shared activation task registrar.'
Assert-Contains $installer 'Set-WinDefaultInputMethodOverride' 'ZIP installer does not contest a competing IME for the default zh-Hans-CN input method.'
Assert-Contains $installer '.InputMethodTips.Insert(0,' 'ZIP installer appends to the language list instead of claiming the preferred (first) position.'
Assert-Contains $keyboard 'Set-WinDefaultInputMethodOverride' 'Standalone keyboard helper does not contest a competing IME for the default zh-Hans-CN input method.'
Assert-Contains $keyboard '.InputMethodTips.Insert(0,' 'Standalone keyboard helper appends to the language list instead of claiming the preferred (first) position.'
Assert-Contains $rollback 'Test-ManagedGyPath' 'Standalone rollback does not protect its managed recovery paths.'
Assert-Contains $rollback '回退目标离线引擎自检失败' 'Standalone rollback does not health-check its target.'
Assert-Contains $rollback 'ActivatePendingLogon' 'Standalone rollback does not remove the redundant ONLOGON activation task.'
Assert-Contains $rollback "activationState = 'active'" 'Standalone rollback does not normalize the restored state to active.'
Assert-Contains $rollback 'Assert-RegisteredGyState' 'Standalone rollback does not read back DLL / Host registry activation.'
Assert-Contains $rollback 'Restart-ActiveGyHost' 'Standalone rollback does not restart the verified restored Host.'
Assert-Contains $rollback 'Write-RecoveryReport' 'Standalone rollback does not persist a durable recovery result.'
Assert-Contains $rollback 'Invoke-PostRecoveryCleanup' 'Standalone rollback does not clean only after successful recovery.'
Assert-Contains $rollback "activationState -eq 'active'" 'Standalone rollback accepts an unverified recovery snapshot.'
Assert-Contains $rollback 'A partial rollback must never strand the machine' 'Standalone rollback does not restore a former verified registration after a partial failure.'
if ($rollback -match '(?m)^\s*return\s+if\s*\(') { throw 'Standalone rollback uses PowerShell return-if syntax that fails at runtime.' }
Assert-Contains $e2e 'Assert-PendingCandidate' 'E2E acceptance does not verify that an upgrade first enters the pending state.'
Assert-Contains $e2e 'Invoke-VerifiedRollback' 'E2E acceptance does not execute a verified rollback.'
Assert-Contains $e2e 'recovery-report.json' 'E2E acceptance does not require a durable rollback report.'
Assert-Contains $e2e 'KeepCandidateActive' 'E2E acceptance cannot restore the candidate after proving rollback.'
Assert-Contains $e2e 'BaselineInstallerPath' 'E2E acceptance can silently substitute an unintended rollback baseline.'
Assert-Contains $e2e 'Assert-VerifiedBaselineInstaller' 'E2E acceptance does not verify the immutable baseline installer before activating it.'
Assert-Contains $e2e '-File $sourceRollbackPath -Elevated' 'E2E acceptance can block on a nested rollback elevation prompt.'
Assert-Contains $inno 'Rollback-GYInput.ps1' 'EXE installer does not ship rollback support.'
Assert-Contains $inno 'Repair-GYInput.ps1' 'EXE installer does not ship one-click repair support.'
Assert-Contains $inno 'SaveCapturedPreviousGyState' 'EXE installer does not preserve an upgrade rollback point.'
Assert-Contains $inno 'CoreConnectorIsNew' 'EXE installer does not distinguish a Host-only update from a core update.'
Assert-Contains $inno 'VerifyActivatedRelease' 'EXE installer does not verify the activated DLL / Host version.'
Assert-Contains $inno 'PendingTaskNameLogon' 'EXE installer does not provide an ONLOGON activation fallback.'
Assert-Contains $inno 'PendingTaskExists' 'EXE installer does not read back activation tasks after creation.'
Assert-Contains $inno 'AcquireActivationMutex' 'EXE installer does not acquire the shared activation mutex.'
Assert-Contains $inno 'Global\GYInputFinalizePending' 'EXE installer does not use the canonical activation mutex name.'
Assert-Contains $inno 'uninsneveruninstall' 'EXE installer may delete shared helper files during uninstall.'
Assert-Contains $inno 'ShouldInstallSharedHelpers' 'EXE installer may overwrite shared helpers from a newer active release.'
Assert-Contains $inno 'SharedActivationHelpersExist' 'EXE installer does not recreate self-cleaned helper files for a future upgrade.'
Assert-Contains $inno 'CompareGyVersions' 'EXE installer lacks numeric version ordering for shared helper protection.'
Assert-Contains $inno 'Check: ShouldInstallSharedHelpers' 'EXE installer does not apply the downgrade guard to shared helper files.'
Assert-Contains $inno 'OtherReleaseIsActive' 'EXE installer does not protect a newer active release during old-version uninstall.'
Assert-Contains $inno 'AppId=GYInput-{#MyAppVersion}' 'EXE installer does not isolate the Inno uninstall identity per version.'
Assert-Contains $inno 'UninstallFilesDir={app}\uninstall-{#MyAppVersion}' 'EXE installer does not isolate uninstall data per version.'
Assert-Contains $inno 'RepairPendingActivation' 'EXE installer does not self-heal a stale pending activation before installing.'
Assert-Contains $inno 'registryVerified' 'EXE installer does not persist registry verification state.'
Assert-Contains $inno 'RELEASE-NOTES.txt' 'EXE installer does not ship version-specific release notes.'
Assert-Contains $inno 'RunPostInstallValidation' 'EXE installer does not run post-install validation.'
Assert-Contains $inno 'Register-GYInputActivationTasks.ps1' 'EXE installer does not delegate task registration to the shared PowerShell registrar.'
Assert-Contains $inno '" -LockAlreadyHeld' 'EXE installer does not register pending activation tasks inside its owning transaction.'
Assert-Contains $inno 'VerifyCapturedPreviousGyState' 'EXE installer does not health-check the rollback snapshot before staging an upgrade.'
Assert-Contains $inno 'HasExistingGyRegistration' 'EXE installer can overwrite an incomplete prior registration without a rollback snapshot.'
Assert-Contains $inno "PreviousHealth, 'active'" 'EXE installer does not mark its captured rollback snapshot as active.'
if ($inno -match '(?m)^\[Run\]') { throw 'EXE installer must not launch a second activation registrar that races its own transaction mutex.' }
Assert-Contains $packaging 'Release notes are missing' 'ZIP package does not require version-specific release notes.'
$notesRoot = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'release\notes'
if (-not (Test-Path -LiteralPath $notesRoot)) { throw 'Version-specific release notes directory is missing.' }
if ($inno.Contains('[UninstallDelete]')) { throw 'EXE installer must not delete shared activation helpers owned by another version.' }
Assert-Contains $inno 'RestoreCapturedPreviousGyState' 'EXE installer cannot safely restore the previous activation state.'
Assert-Contains $verification 'Get-GYReleaseManifest' 'Release verifier does not use the canonical release manifest.'
Assert-Contains $verification 'sourceScripts' 'Release verifier does not compare packaged installer scripts with source.'
Assert-Contains $verification 'Packaged installer script differs from the audited source' 'Release verifier does not reject stale installer scripts.'
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
Assert-Contains $publish 'Get-R2ObjectWithRetry' 'Publish workflow does not retry R2 eventual consistency readbacks.'
Assert-Contains $publish '[switch]$Resume' 'Publish workflow cannot resume a partially uploaded immutable release.'
Assert-Contains $publish 'Existing immutable R2 object differs from the local verified artifact' 'Publish workflow does not compare resumed immutable objects before advancing latest.'
$worker = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\release-service\src\release-worker-v2.js') -Raw
Assert-Contains $worker 'releases/latest.json' 'Download worker is not driven by R2 latest.json.'
if ($worker.Contains('0.4.2')) { throw 'Download worker still contains a hard-coded legacy release version.' }
$hostSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\GyImeHost.cpp') -Raw
$settingsSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\SettingsWindow.cpp') -Raw
Assert-Contains $settingsSource 'Page::Updates' 'Settings window does not expose the version/update page.'
Assert-Contains $settingsSource 'ReadRegisteredVersion' 'Settings window does not compare the registry activation version.'
Assert-Contains $settingsSource 'RELEASE-NOTES.txt' 'Settings window does not load installed release notes.'
Assert-Contains $hostSource 'AddClipboardFormatListener' 'Host no longer registers the clipboard history listener.'
Assert-Contains $hostSource 'SettingsWindow settings_' 'Host no longer owns the settings window.'
Assert-Contains $hostSource 'TrayController tray' 'Host no longer owns the tray controller.'
$candidateHeader = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\CandidateWindow.h') -Raw
Assert-Contains $candidateHeader 'kCandidatesPerPage = 5' 'Candidate contract changed: default row must have five candidates.'
Assert-Contains $candidateHeader 'kExpandedColumns = gy::candidate_layout::ExpandedColumns()' 'Candidate contract changed: expanded grid must have five columns.'
Assert-Contains $candidateHeader 'kExpandedMaxRows = gy::candidate_layout::ExpandedRows(25)' 'Candidate contract changed: expanded grid must have at most five rows.'
$candidateLayout = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\CandidateLayout.h') -Raw
Assert-Contains $candidateLayout 'constexpr unsigned ExpandedColumns() noexcept { return 5; }' 'Candidate contract changed: expanded grid must have exactly five columns.'
Assert-Contains $candidateLayout 'constexpr unsigned ExpandedRows(unsigned candidate_count,' 'Candidate contract changed: expanded grid row calculation is missing.'
$candidateWindow = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\CandidateWindow.cpp') -Raw
$capturePolicy = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\InputCapturePolicy.h') -Raw
Assert-Contains $capturePolicy 'total_candidate_count' 'Candidate capture policy does not use the complete candidate pool.'
$ime = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\GyIme.cpp') -Raw
Assert-Contains $ime 'static_cast<unsigned>(candidates_.size())' 'TSF capture does not pass the complete candidate pool.'
Assert-Contains $candidateWindow 'Do not clamp a normal four-character candidate back into an ellipsis.' 'Candidate renderer must preserve complete four-character words.'
Assert-Contains $candidateWindow 'candidate_font, false' 'Candidate renderer must not ellipsize candidate text.'
Assert-Contains $ime 'if (key == VK_DOWN)' 'Candidate contract changed: Down must expand or page candidates.'
Assert-Contains $ime 'expanded_candidates_ = true' 'Candidate contract changed: first Down must expand the candidate grid.'
Write-Host 'Installer upgrade/rollback/signing smoke: PASS'
