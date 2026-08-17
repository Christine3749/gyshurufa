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
$autoUpdate = Assert-ScriptParses (Join-Path $PSScriptRoot 'AutoUpdate-GYInput.ps1')
$englishLexiconSync = Assert-ScriptParses (Join-Path $PSScriptRoot 'Sync-GYEnglishLexicon.ps1')
$englishLexiconSmoke = Assert-ScriptParses (Join-Path $PSScriptRoot 'EnglishLexiconSyncSmoke.ps1')
$prune = Assert-ScriptParses (Join-Path $PSScriptRoot 'Prune-GYOldVersions.ps1')
$legacyInstallMigration = Assert-ScriptParses (Join-Path $PSScriptRoot 'Migrate-GYLegacyInstallEntries.ps1')
$clientFinalizer = Assert-ScriptParses (Join-Path $PSScriptRoot 'Finalize-GYClientReload.ps1')
$releaseState = Assert-ScriptParses (Join-Path $PSScriptRoot 'Get-GYReleaseState.ps1')
$keepHealth = Assert-ScriptParses (Join-Path $PSScriptRoot 'Get-GYKeepHealth.ps1')
$transaction = Assert-ScriptParses (Join-Path $PSScriptRoot 'GYInputTransaction.ps1')
$taskRegistrar = Assert-ScriptParses (Join-Path $PSScriptRoot 'Register-GYInputActivationTasks.ps1')
$registrationRecovery = Assert-ScriptParses (Join-Path $PSScriptRoot 'Recover-GYIncompleteRegistration.ps1')
$validator = Assert-ScriptParses (Join-Path $PSScriptRoot 'Validate-GYInput.ps1')
$clientProbe = Assert-ScriptParses (Join-Path $PSScriptRoot 'Get-GYLoadedClientState.ps1')
$keyboard = Assert-ScriptParses (Join-Path $PSScriptRoot 'Set-GYKeyboard.ps1')
$e2e = Assert-ScriptParses (Join-Path $PSScriptRoot 'Test-GYInputUpgradeRollback.ps1')
$internalAcceptancePrepare = Assert-ScriptParses (Join-Path $PSScriptRoot '..\Prepare-GYInternalAcceptance.ps1')
$internalAcceptanceRun = Assert-ScriptParses (Join-Path $PSScriptRoot '..\Run-GYInternalAcceptance.ps1')
$packageScript = Assert-ScriptParses (Join-Path $PSScriptRoot '..\package.ps1')
$thinkPadCandidate = Assert-ScriptParses (Join-Path $PSScriptRoot '..\Build-GYThinkPadCandidate.ps1')
$settingsSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\SettingsWindow.cpp') -Raw
Assert-Contains $transaction 'Global\GYInputFinalizePending' 'Shared transaction helper does not define the canonical mutex name.'
Assert-Contains $installer 'Invoke-WithGYInputTransaction' 'ZIP installer does not serialize its full elevated transaction.'
Assert-Contains $installer 'if (-not $isAdmin)' 'ZIP installer does not avoid redundant elevation in an existing Administrator PowerShell.'
Assert-Contains $rollback 'Invoke-WithGYInputTransaction' 'Standalone rollback does not serialize its activation transaction.'
Assert-Contains $rollback 'if (-not $Elevated -and -not $isAdmin)' 'Standalone rollback opens a redundant UAC process even when it is already elevated.'
Assert-Contains $repair 'Invoke-WithGYInputTransaction' 'One-click repair does not serialize its activation transaction.'
Assert-Contains $repair 'Require-PendingActivationComplete' 'One-click repair does not preserve a boot-only pending activation.'
Assert-Contains $repair 'Test-ManagedGyPath' 'One-click repair does not constrain registry targets to managed paths.'
Assert-Contains $repair 'Start-Process -FilePath (Get-X64RegSvr32)' 'One-click repair does not re-register the verified TSF DLL.'
Assert-Contains $repair 'Remove-StaleTransientHelpers' 'One-click repair does not clean expired staged helper files.'
Assert-Contains $repair 'Prune-GYOldVersions.ps1' 'One-click repair does not invoke the audited old-version cleaner.'
Assert-Contains $repair 'Write-RecoveryReport' 'One-click repair does not persist a durable recovery result.'
Assert-Contains $repair 'Remove-LegacyVersionPinnedHostStartup' 'One-click repair does not remove the obsolete version-pinned Host startup value.'
Assert-Contains $legacyInstallMigration 'GYInput-(\d+\.\d+\.\d+)_is1' 'Legacy installed-app migration does not target versioned Inno entries.'
Assert-Contains $legacyInstallMigration '$expectedDisplayName' 'Legacy installed-app migration does not verify the product name before removal.'
Assert-Contains $legacyInstallMigration '0x8F93' 'Legacy installed-app migration does not preserve the exact GY product name.'
Assert-Contains $legacyInstallMigration 'Test-ManagedInstallRoot' 'Legacy installed-app migration may remove entries outside the managed GY folder.'
Assert-Contains $repair 'Get-GYKeepHealth.ps1' 'One-click repair does not trigger Keep 健康体检。'
Assert-Contains $autoUpdate 'Get-FileHash' 'Automatic updater does not verify the installer SHA-256.'
Assert-Contains $autoUpdate 'Get-AuthenticodeSignature' 'Automatic updater does not verify the installer signature.'
Assert-Contains $autoUpdate 'Start-Process -FilePath $installer -Verb RunAs' 'Automatic updater does not launch the standard installer through UAC.'
Assert-Contains $autoUpdate 'update-state.ini' 'Automatic updater does not persist a user-visible local update state.'
Assert-Contains $autoUpdate 'Sync-GYEnglishLexicon.ps1' 'Automatic updater does not trigger the verified English lexicon sync.'
Assert-Contains $autoUpdate 'lexiconStatus' 'Automatic updater does not expose English lexicon sync state.'
Assert-Contains $englishLexiconSync 'gy-shurufa-download.lihouyi7586.workers.dev' 'English lexicon sync is not pinned to the official download Worker.'
Assert-Contains $englishLexiconSync 'Get-FileHash' 'English lexicon sync does not verify SHA-256 before activation.'
Assert-Contains $englishLexiconSync 'english-mixed-state.ini' 'English lexicon sync does not use an atomic local state file.'
Assert-Contains $englishLexiconSmoke 'example.invalid' 'English lexicon smoke does not verify an untrusted manifest boundary.'
Assert-Contains $autoUpdate 'Ensure-UpdatePackage' 'Automatic updater does not prepare a verified reusable package.'
Assert-Contains $autoUpdate '.download' 'Automatic updater can expose a partial download as the cached installer.'
Assert-Contains $autoUpdate '-not $Force -and [DateTime]::TryParse' 'Forced update checks cannot override a user snooze.'
Assert-Contains $autoUpdate 'gy-shurufa-download.lihouyi7586.workers.dev/api/releases/latest' 'Automatic updater is not pinned to the official release API.'
Assert-Contains $autoUpdate 'ToastActionUri' 'Automatic updater cannot receive a Windows toast action.'
Assert-Contains $autoUpdate 'Invoke-Snooze' 'Automatic updater does not implement the deferred reminder action.'
Assert-Contains $autoUpdate 'snoozeUntilUtc' 'Automatic updater does not persist the deferred reminder deadline.'
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
Assert-Contains $clientFinalizer '$StartupTrigger' 'Finalizer does not require its boot-bound scheduled-task trigger.'
Assert-Contains $clientFinalizer 'Get-CurrentBootId' 'Finalizer does not prove that Windows restarted after staging.'
Assert-Contains $clientFinalizer 'Assert-NoRegisteredGyState' 'Finalizer does not safely handle a first installation.'
$finalizerWaitCount = [regex]::Matches($clientFinalizer, '\$mutex\.WaitOne\(0\)').Count
Assert-Contains $taskRegistrar 'Wait-GYInputScheduledTask' 'Activation task registrar does not read back task persistence.'
Assert-Contains $taskRegistrar "Register-ActivationTask `$taskName 'ONSTART'" 'Activation task registrar does not create its primary ONSTART task.'
Assert-Contains $taskRegistrar "Register-ActivationTask `$logonTaskName 'ONLOGON'" 'Activation task registrar lacks a redundant ONLOGON recovery task.'
Assert-Contains $taskRegistrar '/DELAY 0000:20' 'Activation tasks can run before the system volume and pending state settle.'
Assert-Contains $clientFinalizer "`$logonTaskName = 'GYInput\ActivatePendingLogon'" 'Finalizer cannot remove the redundant activation task after success.'
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
$buildInstaller = Assert-ScriptParses (Join-Path $PSScriptRoot '..\build-installer.ps1')
$finalize = Assert-ScriptParses (Join-Path $PSScriptRoot '..\Finalize-GYRelease.ps1')
$publish = Assert-ScriptParses (Join-Path $PSScriptRoot '..\Publish-GYRelease.ps1')
$inno = Get-Content -LiteralPath $InnoPath -Raw
Assert-Contains $inno 'english-lexicon\*' 'Inno package does not install the bundled offline English baseline.'
Assert-Contains $packageScript '(Join-Path $binaryRoot ''english-lexicon'')' 'Release packaging does not include the bundled offline English baseline.'
Assert-Contains $installer '[switch]$Rollback' 'ZIP installer does not expose rollback.'
Assert-Contains $installer 'Test-ManagedGyPath' 'ZIP installer rollback does not verify managed paths.'
Assert-Contains $installer 'Start-Process -FilePath $health' 'ZIP installer rollback does not health-check its target.'
Assert-Contains $installer 'Save-PreviousGyState' 'ZIP installer does not preserve an upgrade rollback point.'
Assert-Contains $installer "activationState = 'active'" 'ZIP installer does not save a verified active rollback snapshot.'
Assert-Contains $installer 'registryVerified = $true' 'ZIP installer rollback snapshot is not explicitly registry-verified.'
Assert-Contains $installer 'activationState = $ActivationState' 'ZIP installer does not record core activation state.'
Assert-Contains $installer "activationState = 'pending'" 'ZIP installer does not record explicit pending state.'
Assert-Contains $installer "Write-GyActivationState 'staged'" 'ZIP installer does not record staged state before pending.'
Assert-Contains $installer 'Require-PendingActivationComplete' 'ZIP installer can bypass an existing boot-only pending activation.'
Assert-Contains $installer 'stagedBootId' 'ZIP installer does not bind activation to a later Windows boot.'
if ($installer -match 'Try-FinalizePendingActivation') { throw 'ZIP installer must never activate a staged TSF release in the current session.' }
Assert-Contains $validator 'Get-GyCoreVersionFromPath' 'Post-install validation does not derive the registered TSF version.'
Assert-Contains $validator 'Get-RunningGyHosts' 'Post-install validation does not inspect the actual running Host version.'
Assert-Contains $validator "-Name 'GYInputHost'" 'Post-install validation does not reject the obsolete version-pinned Host startup value.'
Assert-Contains $validator 'Host Logo 存在' 'Post-install validation does not verify the Host Logo.'
Assert-Contains $validator 'TSF Logo 存在' 'Post-install validation does not verify the TSF Logo.'
Assert-Contains $rollback "action = 'rollback'" 'Rollback does not persist an explicit recovery action.'
Assert-Contains $rollback 'Test-RollbackTargetState' 'Rollback cannot recover a valid legacy installer snapshot.'
Assert-Contains $e2e 'Assert-RollbackSnapshot' 'Upgrade/rollback acceptance does not validate the saved rollback snapshot.'
Assert-Contains $settingsSource 'ReadRegisteredDllVersion' 'Settings page does not read the actual registered TSF version.'
Assert-Contains $settingsSource 'registered_core_version_' 'Settings page does not retain the actual TSF version.'
Assert-Contains $settingsSource 'versions_consistent_' 'Settings page does not display real Host/DLL/TSF consistency.'
Assert-Contains $settingsSource 'BeginUpdateRepair' 'Settings update page does not provide a repair action.'
Assert-Contains $settingsSource 'Repair-GYInput.ps1' 'Settings repair action does not use the installed maintenance script.'
Assert-Contains $settingsSource 'ShellExecuteExW' 'Settings repair action does not request administrator elevation.'
Assert-Contains $settingsSource 'BeginUpdateRollback' 'Settings update page does not provide a one-click rollback action.'
Assert-Contains $settingsSource 'Rollback-GYInput.ps1' 'Settings rollback action does not use the installed rollback script.'
Assert-Contains $settingsSource 'InstalledRollbackVersion' 'Settings update page cannot display a rollback target.'
Assert-Contains $settingsSource 'BeginAutomaticUpdate' 'Settings update page does not expose the automatic update trigger.'
Assert-Contains $settingsSource 'kAutomaticUpdateComplete' 'Settings page cannot receive the automatic updater completion result.'
Assert-Contains $settingsSource 'BeginUpdateCheck' 'Settings update page does not let the user force a safe update check.'
Assert-Contains $settingsSource 'kAutomaticUpdateCheckComplete' 'Settings page cannot receive the update-check completion result.'
Assert-Contains $settingsSource '-Action Check -Force' 'Settings page does not perform an explicit non-installing update check.'
Assert-Contains $settingsSource 'update-state.ini' 'Settings page does not display the local automatic update state.'
Assert-Contains $installer 'Test-ThisReleaseActive' 'ZIP installer does not verify that registry activation matches the staged release.'
Assert-Contains $installer 'Write-GyStateAtomically' 'ZIP installer does not atomically persist activation state.'
Assert-Contains $installer 'release-notes.txt' 'ZIP installer does not install version-specific release notes.'
Assert-Contains $installer 'Invoke-InstalledValidation' 'ZIP installer does not run post-install validation.'
Assert-Contains $installer 'Should-PreserveExistingPendingHelpers' 'ZIP installer may downgrade shared activation helpers from a newer active release.'
Assert-Contains $installer 'A failed task registration must not leave a false pending marker behind.' 'ZIP installer does not clean a failed pending-task registration transaction.'
Assert-Contains $installer 'Register-GYInputActivationTasks.ps1' 'ZIP installer does not use the shared activation task registrar.'
Assert-Contains $inno 'AutoUpdate-GYInput.ps1' 'Inno package does not include the automatic updater.'
Assert-Contains $inno 'Sync-GYEnglishLexicon.ps1' 'Inno package does not include the English lexicon sync helper.'
Assert-Contains $inno 'GYInput.Desktop' 'EXE installer does not register the stable toast AppUserModelID.'
Assert-Contains $installer 'Set-WinDefaultInputMethodOverride' 'ZIP installer does not contest a competing IME for the default zh-Hans-CN input method.'
Assert-Contains $installer '.InputMethodTips.Insert(0,' 'ZIP installer appends to the language list instead of claiming the preferred (first) position.'
Assert-Contains $keyboard 'Set-WinDefaultInputMethodOverride' 'Standalone keyboard helper does not contest a competing IME for the default zh-Hans-CN input method.'
Assert-Contains $keyboard '.InputMethodTips.Insert(0,' 'Standalone keyboard helper appends to the language list instead of claiming the preferred (first) position.'
Assert-Contains $keyboard 'Refresh-GYInputIndicator' 'Standalone keyboard helper does not refresh the current Windows language-bar session after an install.'
Assert-Contains $keyboard 'RequireActiveVersion' 'Keyboard helper can expose GY before the staged version is active.'
Assert-Contains $keyboard 'Software\Microsoft\Windows\CurrentVersion\Run' 'Keyboard completion is not durable across a slow boot activation.'
Assert-Contains $keyboard 'Clear-DurableKeyboardCompletion' 'Keyboard completion cannot remove its persistent retry after verified success.'
Assert-Contains $keyboard '$updatedTips -contains $tipId' 'Keyboard completion does not read back the current user TIP before declaring success.'
Assert-Contains $keyboard 'Remove-LegacyVersionPinnedHostStartup' 'Keyboard completion does not remove the obsolete version-pinned Host startup value.'
Assert-Contains $keyboard 'Reconcile-CurrentUserGyHost' 'Keyboard completion does not reconcile the actual Host after reboot.'
Assert-Contains $keyboard 'Test-ManagedGyHostPath $processPath' 'Host reconciliation can terminate an unmanaged process.'
Assert-Contains $keyboard 'Stop-Process -Id $process.Id' 'Host reconciliation cannot replace a verified obsolete managed Host.'
if ($keyboard.Contains('CurrentVersion\RunOnce')) { throw 'Keyboard completion must not use lossy RunOnce retry semantics.' }
if ($installer -match '(?im)^\s*Stop-Process\b' -or
    $repair -match '(?im)^\s*Stop-Process\b') {
  throw 'Install and repair must never terminate a process.'
}
$keyboardStopCount = [regex]::Matches($keyboard, '(?im)^\s*Stop-Process\s+-Id\s+\$process\.Id\b').Count
if ($keyboardStopCount -ne 1) { throw "Post-reboot Host reconciliation must contain exactly one scoped Host stop; found $keyboardStopCount." }
Assert-Contains $installer '$installedSharedIcon' 'ZIP installer does not install the stable shared GY input-method icon.'
Assert-Contains $validator '共享输入法 Logo 存在' 'Post-install validation does not verify the stable shared input-method icon.'
Assert-Contains $validator 'Get-GYLoadedClientState.ps1' 'Post-install validation does not inspect already-open clients holding an old TSF DLL.'
Assert-Contains $clientProbe 'inaccessibleProcessCount' 'Client reload probe does not distinguish inaccessible processes from a clean scan.'
Assert-Contains $clientProbe 'modulePath' 'Client reload probe does not report the loaded GY TSF module path.'
Assert-Contains $rollback 'Test-ManagedGyPath' 'Standalone rollback does not protect its managed recovery paths.'
Assert-Contains $rollback '回退目标离线引擎自检失败' 'Standalone rollback does not health-check its target.'
Assert-Contains $rollback 'ActivatePendingLogon' 'Standalone rollback does not remove the redundant ONLOGON activation task.'
Assert-Contains $rollback "activationState = 'active'" 'Standalone rollback does not normalize the restored state to active.'
Assert-Contains $rollback 'Assert-RegisteredGyState' 'Standalone rollback does not read back DLL / Host registry activation.'
Assert-Contains $rollback 'Restart-ActiveGyHost' 'Standalone rollback does not restart the verified restored Host.'
Assert-Contains $rollback 'Remove-LegacyVersionPinnedHostStartup' 'Standalone rollback does not remove the obsolete version-pinned Host startup value.'
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
Assert-Contains $inno 'Every install is stage-only' 'EXE installer does not enforce one stage-only path for all updates.'
if ($inno.Contains("'/s `"' + StableDllPath")) { throw 'EXE installer retains a direct current-session TSF activation path.' }
if ($inno -match '/SC\s+ONLOGON') { throw 'EXE installer must never create an ONLOGON activation task.' }
Assert-Contains $inno 'PendingTaskExists' 'EXE installer does not read back activation tasks after creation.'
Assert-Contains $inno 'AcquireActivationMutex' 'EXE installer does not acquire the shared activation mutex.'
Assert-Contains $inno 'Global\GYInputFinalizePending' 'EXE installer does not use the canonical activation mutex name.'
Assert-Contains $inno 'uninsneveruninstall' 'EXE installer may delete shared helper files during uninstall.'
Assert-Contains $inno 'ShouldInstallSharedHelpers' 'EXE installer may overwrite shared helpers from a newer active release.'
Assert-Contains $inno 'SharedActivationHelpersExist' 'EXE installer does not recreate self-cleaned helper files for a future upgrade.'
Assert-Contains $inno 'CompareGyVersions' 'EXE installer lacks numeric version ordering for shared helper protection.'
Assert-Contains $inno 'Check: ShouldInstallSharedHelpers' 'EXE installer does not apply the downgrade guard to shared helper files.'
Assert-Contains $inno 'OtherReleaseIsActive' 'EXE installer does not protect a newer active release during old-version uninstall.'
Assert-Contains $inno 'AppId={#MyAppId}' 'EXE installer does not retain one stable product identity across updates.'
Assert-Contains $inno 'UninstallFilesDir={app}\uninstall' 'EXE installer does not retain one stable uninstaller across updates.'
Assert-Contains $inno 'Migrate-GYLegacyInstallEntries.ps1' 'EXE installer does not ship the legacy installed-app migration.'
Assert-Contains $clientFinalizer 'Invoke-LegacyInstallMigration' 'Boot Finalizer does not migrate legacy installed-app entries after activation.'
Assert-Contains $inno 'RequirePendingActivationComplete' 'EXE installer can bypass an existing boot-only pending activation.'
Assert-Contains $inno 'registryVerified' 'EXE installer does not persist registry verification state.'
Assert-Contains $inno 'RELEASE-NOTES.txt' 'EXE installer does not ship version-specific release notes.'
if ($inno -match 'RunPendingFinalizerNow') { throw 'EXE installer must never activate a staged TSF release in the current session.' }
Assert-Contains $inno 'stable path' 'EXE installer does not document the stable shared input-method icon path.'
Assert-Contains $inno 'DestName: "gy.ico"' 'EXE installer does not install the stable shared input-method icon.'
Assert-Contains $inno 'stagedBootId' 'EXE installer does not bind activation to a later Windows boot.'
Assert-Contains $inno 'Register-GYInputActivationTasks.ps1' 'EXE installer does not delegate task registration to the shared PowerShell registrar.'
Assert-Contains $inno 'RemoveLegacyVersionPinnedHostStartup' 'EXE installer does not remove the obsolete version-pinned Host startup value.'
Assert-Contains $inno '-ReconcileHost' 'EXE installer does not request post-reboot Host reconciliation.'
Assert-Contains $installer 'Remove-LegacyVersionPinnedHostStartup' 'ZIP installer does not remove the obsolete version-pinned Host startup value.'
Assert-Contains $installer '-ReconcileHost' 'ZIP installer does not request post-reboot Host reconciliation.'
Assert-Contains $inno '" -LockAlreadyHeld' 'EXE installer does not register pending activation tasks inside its owning transaction.'
Assert-Contains $inno 'VerifyCapturedPreviousGyState' 'EXE installer does not health-check the rollback snapshot before staging an upgrade.'
Assert-Contains $inno 'HasExistingGyRegistration' 'EXE installer can overwrite an incomplete prior registration without a rollback snapshot.'
Assert-Contains $inno 'RecoverIncompletePreviousGyRegistration' 'EXE installer cannot recover missing Host metadata for a verified active rollback target.'
Assert-Contains $inno "ExpandConstant('{app}\Recover-GYIncompleteRegistration.ps1')" 'EXE installer launches recovery from a temporary directory that endpoint security may block.'
Assert-Contains $registrationRecovery 'registration-recovery.error.log' 'Host metadata recovery does not preserve a content-free failure reason for field diagnosis.'
Assert-Contains $registrationRecovery '$state.registryVerified -ne $true' 'Host metadata recovery does not require a verified durable active snapshot.'
Assert-Contains $registrationRecovery 'Test-SamePath $registeredDll $dll' 'Host metadata recovery can combine state with a different registered TSF DLL.'
Assert-Contains $registrationRecovery 'Start-Process -FilePath $health' 'Host metadata recovery does not health-check the active rollback target.'
if ($registrationRecovery -match '(?i)regsvr32|Set-Win|Remove-Item|Stop-Process') { throw 'Host metadata recovery can mutate the live TSF registration, user keyboard list, processes, or installed files.' }
Assert-Contains $installer 'Recover-GYIncompleteRegistration.ps1' 'ZIP installer cannot recover verified incomplete Host metadata before capturing rollback state.'
Assert-Contains $inno "PreviousHealth, 'active'" 'EXE installer does not mark its captured rollback snapshot as active.'
if ($inno -match '(?m)^\[Run\]') { throw 'EXE installer must not launch a second activation registrar that races its own transaction mutex.' }
Assert-Contains $packaging 'Release notes are missing' 'ZIP package does not require version-specific release notes.'
$notesRoot = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'release\notes'
if (-not (Test-Path -LiteralPath $notesRoot)) { throw 'Version-specific release notes directory is missing.' }
if ($inno.Contains('[UninstallDelete]')) { throw 'EXE installer must not delete shared activation helpers owned by another version.' }
Assert-Contains $inno 'RestoreCapturedPreviousStateFile' 'EXE installer cannot restore the previous durable state after staging failure.'
Assert-Contains $verification 'Get-GYReleaseManifest' 'Release verifier does not use the canonical release manifest.'
Assert-Contains $verification 'sourceScripts' 'Release verifier does not compare packaged installer scripts with source.'
Assert-Contains $verification 'Packaged installer script differs from the audited source' 'Release verifier does not reject stale installer scripts.'
Assert-Contains $verification 'Package release.json matches Windows package/core/host' 'Release verifier does not validate package version consistency.'
Assert-Contains $signing 'Set-AuthenticodeSignature' 'Signing workflow does not sign release binaries.'
Assert-Contains $signing 'Verify-GYRelease.ps1' 'Signing workflow does not force final verification.'
Assert-Contains $verification 'Get-AuthenticodeSignature' 'Release verifier does not inspect Authenticode status.'
Assert-Contains $verification '[switch]$RequireSignature' 'Release verifier cannot enforce public-Beta signing.'
Assert-Contains $verification 'Installer SHA-256 and byte size match canonical release.json.' 'Release verifier does not bind the installer to the canonical hash and byte size.'
Assert-Contains $packaging 'Assert-GYReleaseApproval' 'Release payload preparation can bypass the recorded human approval gate.'
Assert-Contains $buildInstaller 'Assert-GYReleaseApproval' 'EXE installer creation can bypass the recorded human approval gate.'
Assert-Contains $finalize 'Assert-GYReleaseApproval' 'Finalization can turn a draft into a candidate without recorded human approval.'
Assert-Contains $signing 'Assert-GYReleaseApproval' 'Signing can proceed without recorded human approval.'
Assert-Contains $publish 'Assert-GYReleaseApproval' 'Publishing can proceed without recorded human approval.'
Assert-Contains $verification 'Assert-GYReleaseApproval' 'Release verification does not require recorded human approval.'
Assert-Contains $internalAcceptancePrepare 'GY_BUILD_HOST_SMOKE=OFF' 'Internal acceptance incorrectly builds the Host with test-only behavior enabled.'
Assert-Contains $internalAcceptancePrepare 'GY_TESTING. Refusing' 'Internal acceptance does not reject a test-mode Host project.'
Assert-Contains $internalAcceptancePrepare 'publicReleaseArtifact = $false' 'Internal acceptance output is not explicitly marked non-public.'
Assert-Contains $internalAcceptancePrepare 'INTERNAL-ACCEPTANCE-NOT-FOR-DISTRIBUTION.txt' 'Internal acceptance output lacks its non-distribution marker.'
Assert-Contains $internalAcceptanceRun "Assert-ActiveVersion `$expectedBaseline 'Preflight'" 'Internal acceptance does not demand the verified 0.10.95 baseline first.'
Assert-Contains $internalAcceptanceRun 'Assert-BaselineSnapshot' 'Internal acceptance does not verify the exact rollback snapshot.'
Assert-Contains $internalAcceptanceRun '[switch]$AllowLiveMachineActivation' 'Internal acceptance can activate the live input method without an explicit per-run opt-in.'
Assert-Contains $internalAcceptanceRun 'Refusing live input-method activation.' 'Internal acceptance does not reject accidental live activation.'
Assert-Contains $internalAcceptanceRun '$expectedCandidate = (Get-Content' 'Internal acceptance pins its payload paths to a stale candidate version.'
Assert-Contains $internalAcceptanceRun 'Assert-CandidatePayloadActivated' 'Internal acceptance can test stale candidate binaries left by an earlier rehearsal.'
Assert-Contains $internalAcceptanceRun 'finally {' 'Internal acceptance can leave a candidate active after a failed rehearsal.'
Assert-Contains $internalAcceptanceRun 'RESULT: PASS; $expectedCandidate was not retained.' 'Internal acceptance does not make its non-retention contract explicit.'
Assert-Contains $internalAcceptanceRun 'Get-InputModeSnapshot' 'Internal acceptance does not snapshot the user InputMode state.'
Assert-Contains $internalAcceptanceRun 'Assert-InputModeUnchanged' 'Internal acceptance does not fail when upgrade changes the user InputMode state.'
Assert-Contains $internalAcceptanceRun 'Restore-InputModeSnapshot' 'Internal acceptance cannot restore a changed user InputMode state during cleanup.'
Assert-Contains $rollback 'WaitForExit($cleanupTimeoutMilliseconds)' 'Rollback can wait forever for non-critical old-version cleanup.'
Assert-Contains $rollback 'Stop-Process -Id $result.Id' 'Rollback cannot end its own stalled cleanup helper.'
if ($packaging.Contains('Compress-Archive')) { throw 'Package preparation must not create a ZIP before final release metadata is verified.' }
Assert-Contains $finalize 'Copy-Item -LiteralPath $manifestPath -Destination $packageManifest -Force' 'Finalize must embed the final canonical release.json before creating the ZIP.'
$manifestModule = Assert-ScriptParses (Join-Path $PSScriptRoot '..\ReleaseManifest.psm1')
Assert-Contains $manifestModule 'Windows setupFile does not match its version.' 'Release manifest does not enforce versioned installer naming.'
Assert-Contains $manifestModule 'PENDING-PACKAGE-VERIFICATION' 'Release manifest does not distinguish an unfinished draft from a publishable artifact.'
Assert-Contains $manifestModule "'0.12.6'" 'Withdrawn 0.12.6 can re-enter the package or publication pipeline.'
Assert-Contains $manifestModule "'0.12.7'" 'Withdrawn 0.12.7 can re-enter the package or publication pipeline.'
Assert-Contains $manifestModule "'0.12.8'" 'Withdrawn 0.12.8 can re-enter the package or publication pipeline.'
Assert-Contains $manifestModule "'0.12.9'" 'Withdrawn 0.12.9 can re-enter the package or publication pipeline.'
Assert-Contains $manifestModule "'0.12.10'" 'Withdrawn 0.12.10 can re-enter the package or publication pipeline.'
Assert-Contains $manifestModule 'Release approval is missing' 'Release approval boundary does not fail closed when the approval record is absent.'
Assert-Contains $manifestModule 'target-test-distribution' 'Release manifest module cannot represent an approved candidate awaiting target-machine acceptance.'
Assert-Contains $manifestModule 'pending-on-target' 'Candidate distribution approval cannot honestly retain pending target acceptance.'
Assert-Contains $manifestModule 'Globalization.CultureInfo]::InvariantCulture' 'Release approval timestamp parsing is not compatible with Windows PowerShell.'
Assert-Contains $publish 'Atomically advance verified cross-platform latest pointer' 'Publish workflow does not atomically switch the R2 latest pointer last.'
Assert-Contains $publish '-RequireSignature:$requireSignature' 'Publish workflow does not require signatures for stable releases.'
Assert-Contains $publish 'CandidateOnly' 'Publish workflow cannot isolate a candidate from the shared latest pointer.'
Assert-Contains $publish 'Assert-GYCandidateDistributionApproval' 'Candidate-only publication cannot use the honest target-test distribution approval.'
Assert-Contains $publish '-CandidateDistribution:$CandidateOnly' 'Candidate publication does not keep verification in target-test distribution mode.'
Assert-Contains $publish 'candidates/windows/$Version/release.json' 'Candidate manifest is not stored outside the shared latest path.'
Assert-Contains $publish 'releases/latest.json (stable) was not changed' 'Candidate publication does not explicitly preserve the shared latest pointer.'
Assert-Contains $publish 'Get-R2ObjectWithRetry' 'Publish workflow does not retry R2 eventual consistency readbacks.'
Assert-Contains $publish '[switch]$Resume' 'Publish workflow cannot resume a partially uploaded immutable release.'
Assert-Contains $publish 'Existing immutable R2 object differs from the local verified artifact' 'Publish workflow does not compare resumed immutable objects before advancing latest.'
$worker = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\release-service\src\release-worker-v2.js') -Raw
Assert-Contains $worker 'releases/latest.json' 'Download worker is not driven by R2 latest.json.'
Assert-Contains $worker 'candidates/windows/${version}/release.json' 'Download worker cannot serve an immutable candidate version without changing latest.'
Assert-Contains $worker '/download/candidate/windows/' 'Download worker does not expose a version-pinned candidate download route.'
Assert-Contains $worker 'lexicons/english-mixed/manifest.json' 'Download worker does not expose the versioned English lexicon manifest.'
Assert-Contains $worker '/api/ciku/ime/lexicon/${manifest.version}' 'Download worker does not expose an immutable English lexicon route.'
if ($worker.Contains('0.4.2')) { throw 'Download worker still contains a hard-coded legacy release version.' }
$hostSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\GyImeHost.cpp') -Raw
$settingsSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\SettingsWindow.cpp') -Raw
$notificationSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\UpdateNotification.cpp') -Raw
Assert-Contains $settingsSource 'Page::Updates' 'Settings window does not expose the version/update page.'
Assert-Contains $settingsSource 'ReadRegisteredVersion' 'Settings window does not compare the registry activation version.'
Assert-Contains $settingsSource 'RELEASE-NOTES.txt' 'Settings window does not load installed release notes.'
Assert-Contains $hostSource 'AddClipboardFormatListener' 'Host no longer registers the clipboard history listener.'
Assert-Contains $hostSource 'SettingsWindow settings_' 'Host no longer owns the settings window.'
Assert-Contains $hostSource 'TrayController tray' 'Host no longer owns the tray controller.'
Assert-Contains $hostSource 'RegisterGyInputProtocol' 'Host does not register the per-user toast action protocol.'
Assert-Contains $hostSource 'Software\\Classes\\gyinput' 'Host does not register the gyinput protocol under the current user.'
Assert-Contains $hostSource '-ToastActionUri' 'Host protocol does not dispatch toast actions to the updater.'
Assert-Contains $notificationSource 'ToastNotificationManager' 'Host update notification does not use the Windows Toast API.'
Assert-Contains $notificationSource 'gyinput://update/install' 'Update notification has no install action.'
Assert-Contains $notificationSource 'gyinput://update/snooze' 'Update notification has no snooze action.'
$candidateHeader = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\CandidateWindow.h') -Raw
Assert-Contains $candidateHeader 'kCandidatesPerPage = gy::candidate_presentation::CompactCapacity()' 'Candidate contract changed: default row must use the presentation policy.'
Assert-Contains $candidateHeader 'kExpandedColumns = gy::candidate_layout::ExpandedColumns()' 'Candidate contract changed: expanded grid must have five columns.'
Assert-Contains $candidateHeader 'kExpandedMaxRows = gy::candidate_layout::ExpandedRows(25)' 'Candidate contract changed: expanded grid must have at most five rows.'
$candidateLayout = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\CandidateLayout.h') -Raw
Assert-Contains $candidateLayout 'constexpr unsigned ExpandedColumns() noexcept { return 5; }' 'Candidate contract changed: expanded grid must have exactly five columns.'
Assert-Contains $candidateLayout 'constexpr unsigned ExpandedRows(unsigned candidate_count,' 'Candidate contract changed: expanded grid row calculation is missing.'
$candidatePresentation = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\CandidatePresentationPolicy.h') -Raw
Assert-Contains $candidatePresentation 'constexpr unsigned CompactCapacity() noexcept { return 5; }' 'Candidate contract changed: compact surfaces must show five candidates.'
Assert-Contains $candidatePresentation 'gy::english_candidates::kCompactVisible' 'English strip capacity is no longer bound to the typed English candidate policy.'
Assert-Contains $thinkPadCandidate "'/DMyThinkPadCandidate=1'" 'ThinkPad candidate does not opt into private per-monitor interface calibration.'
Assert-Contains $inno "SetIniString('Appearance', 'CandidateScale', '0', ThinkPadSettingsPath)" 'ThinkPad candidate cannot persist automatic per-monitor interface scale.'
$thinkPadScaleWrite = $inno.IndexOf("SetIniString('Appearance', 'CandidateScale', '0', ThinkPadSettingsPath)")
$pendingActivationWrite = $inno.IndexOf('ActivationPending := True')
if ($thinkPadScaleWrite -lt 0 -or $pendingActivationWrite -lt 0 -or $thinkPadScaleWrite -ge $pendingActivationWrite) {
  throw 'ThinkPad automatic display calibration must succeed before any pending activation state is recorded.'
}
Assert-Contains $candidatePresentation 'gy::english_candidates::kExpandedVisible' 'English list capacity is no longer bound to the typed English candidate policy.'
Assert-Contains $candidatePresentation 'return purpose == Purpose::ChineseConversion' 'English expansion is not structurally excluded.'
Assert-Contains $candidatePresentation 'Surface::EnglishList' 'English completion no longer exposes its bounded explicit list.'
Assert-Contains $candidatePresentation 'constexpr bool UsesNumericShortcuts' 'English list lost the structural no-number-shortcuts guard.'
if ($candidatePresentation.Contains('EnglishCorrectionStrip')) {
  throw 'English presentation still exposes a legacy correction-only surface.'
}
$candidateWindow = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\CandidateWindow.cpp') -Raw
$capturePolicy = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\InputCapturePolicy.h') -Raw
$nativeCmake = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\CMakeLists.txt') -Raw
$versionResource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\GyVersion.rc.in') -Raw
$realAppRegression = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\EnRealAppRegression.cpp') -Raw
Assert-Contains $capturePolicy 'total_candidate_count' 'Candidate capture policy does not use the complete candidate pool.'
Assert-Contains $nativeCmake 'GY_VERSION_RESOURCE_COMMAS' 'Native binaries do not derive a Windows version resource from the canonical release version.'
Assert-Contains $nativeCmake 'GyImeHostVersion.rc' 'Host does not embed a canonical Windows file version resource.'
Assert-Contains $nativeCmake 'GY_HEALTH_READONLY_INPUT_MODE' 'Installed health check can still read or write the shared user input mode.'
Assert-Contains $versionResource 'ProductVersion' 'Windows version resource does not expose product version metadata.'
Assert-Contains $nativeCmake 'available in both production' 'Real-window regression is not available for a production-mode candidate build.'
Assert-Contains $realAppRegression 'must never write HKCU or settings.ini' 'Real-app regression no longer documents its no-state-mutation boundary.'
Assert-Contains $realAppRegression 'InputModeRestoreGuard' 'Real-app regression can leave the user in a modified input mode after a failed Shift diagnostic.'
Assert-Contains $realAppRegression 'mode_restored_after_normal_test' 'Real-app regression does not record whether its cleanup restored the original mode.'
Assert-Contains $realAppRegression 'SendShiftedVirtualKey' 'Real-app regression does not verify direct symbol entry in a sensitive field.'
Assert-Contains $realAppRegression 'CapsLockRestoreGuard' 'Real-app regression is non-deterministic when the tester has Caps Lock enabled.'
Assert-Contains $realAppRegression 'SendVirtualKey(VK_RETURN)' 'Real-app regression moves focus before committing the EN candidate.'
if ($realAppRegression.Contains('RegSetValueExW') -or $realAppRegression.Contains('RegCreateKeyExW') -or $realAppRegression.Contains('WritePrivateProfile')) {
  throw 'Real-app regression must not write registry or settings state.'
}
$ime = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\GyIme.cpp') -Raw
if ($ime.Contains('ReadAutomationInputScope') -or $ime.Contains('uiautomation.h')) { throw 'TSF key paths must not use cross-process UI Automation.' }
Assert-Contains $ime 'input_scope_manual_override_' 'TSF cannot preserve an explicit per-field user mode choice.'
Assert-Contains $ime 'EnterNativeSensitiveDirectMode' 'Native password/PIN controls do not have a first-key direct-input boundary.'
Assert-Contains $ime 'before consulting the previous TSF context' 'Password/PIN first-key guard no longer documents the stale-context boundary.'
Assert-Contains $ime 'TF_ES_ASYNC | TF_ES_READ' 'TSF input-scope refresh is not asynchronous.'
Assert-Contains $ime 'Scope probes are scheduled on focus and normal edit notifications' 'TSF key path may still schedule a scope probe.'
Assert-Contains $ime 'static_cast<unsigned>(candidates_.size())' 'TSF capture does not pass the complete candidate pool.'
Assert-Contains $ime 'chinese_grid_open_' 'Chinese grid state is not explicitly separated from English suggestions.'
Assert-Contains $ime 'Preserve the current user''s enabled GY language profile across upgrades.' 'Normal registration can still discard the enabled GY profile during an upgrade.'
$profileUnregisterCount = [regex]::Matches($ime, 'profiles->UnregisterProfile\(').Count
if ($profileUnregisterCount -ne 1) { throw "UnregisterProfile must be reachable only from uninstall; found $profileUnregisterCount calls." }
if ($ime.Contains('expanded_candidates_')) { throw 'The shared expanded candidate state can leak Chinese grid behavior into EN.' }
Assert-Contains $candidateWindow 'Do not clamp a normal four-character candidate back into an ellipsis.' 'Candidate renderer must preserve complete four-character words.'
Assert-Contains $candidateWindow 'candidate_font, false' 'Candidate renderer must not ellipsize candidate text.'
Assert-Contains $candidateWindow 'kEnglishCandidateGap = 8' 'English candidates have regressed to cramped visual spacing.'
Assert-Contains $candidateWindow 'kEnglishTextOverhangGuard = 3' 'Final Latin glyphs can be clipped at the candidate boundary.'
Assert-Contains $candidateWindow 'English has no disclosure path at all' 'English renderer no longer documents the no-expand-control boundary.'
Assert-Contains $ime 'if (key == VK_DOWN)' 'Candidate contract changed: Down must expand or page candidates.'
Assert-Contains $ime 'chinese_grid_open_ = true' 'Candidate contract changed: first Down must open the Chinese candidate grid.'
Write-Host 'Installer upgrade/rollback/signing smoke: PASS'
