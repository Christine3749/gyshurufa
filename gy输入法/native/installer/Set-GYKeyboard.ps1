param(
  [switch]$Add,
  [switch]$Remove,
  [string]$RequireActiveVersion = '',
  [switch]$RetryAtNextLogon,
  [ValidateRange(0, 300)][int]$WaitForActivationSeconds = 0
)

$ErrorActionPreference = 'Stop'
if ($Add -eq $Remove) { throw 'Specify exactly one of -Add or -Remove.' }

$completionRunKey = 'Software\Microsoft\Windows\CurrentVersion\Run'
$completionRunName = 'GYInputCompleteKeyboard'

function Save-DurableKeyboardCompletion {
  if (-not $RetryAtNextLogon) { return }
  $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $command = '"' + $powershell + '" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' +
             $PSCommandPath + '" -Add -RequireActiveVersion "' + $RequireActiveVersion +
             '" -RetryAtNextLogon -WaitForActivationSeconds ' + $WaitForActivationSeconds
  $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($completionRunKey)
  try { $key.SetValue($completionRunName, $command, [Microsoft.Win32.RegistryValueKind]::String) } finally { $key.Dispose() }
}

function Clear-DurableKeyboardCompletion {
  $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($completionRunKey, $true)
  if (-not $key) { return }
  try { $key.DeleteValue($completionRunName, $false) } finally { $key.Dispose() }
}

if ($Add) { Save-DurableKeyboardCompletion }
if ($Remove) { Clear-DurableKeyboardCompletion }

function Test-RequiredVersionActive {
  if ([string]::IsNullOrWhiteSpace($RequireActiveVersion)) { return $true }
  $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('Software\GYInput')
  if (-not $key) { return $false }
  try { return [string]$key.GetValue('HostVersion') -eq $RequireActiveVersion } finally { $key.Dispose() }
}

if ($Add -and $RequireActiveVersion) {
  $deadline = [DateTime]::UtcNow.AddSeconds($WaitForActivationSeconds)
  while (-not (Test-RequiredVersionActive) -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Seconds 1
  }
  if (-not (Test-RequiredVersionActive)) {
    # The persistent Run value remains until a later logon verifies success.
    # RunOnce was lossy when Windows launched this helper before boot activation
    # had completed: the retry written by the running command could be deleted
    # as part of RunOnce cleanup, stranding the user in Windows ENG.
    exit 2
  }
}

$tipId = '0804:{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}{5F689D3E-73E3-4C2B-979A-2DD86E438D6F}'
$languages = Get-WinUserLanguageList
$chinese = $languages | Where-Object LanguageTag -eq 'zh-Hans-CN' | Select-Object -First 1
if (-not $chinese) { throw 'Simplified Chinese (China) is not installed. Add it in Windows Settings first.' }

if ($Add) {
  # Remove every historical copy before adding the single canonical TIP. List<T>
  # Remove only deletes one item, which previously let duplicates survive each
  # reinstall and eventually appear repeatedly in Windows language UI.
  while ($chinese.InputMethodTips.Remove($tipId)) {}
  # Insert at the front, not appended: Windows treats a language's first tip
  # as its preferred one, and a competing IME (e.g. Tencent WeType) installed
  # either before or after GY would otherwise keep that position indefinitely.
  $chinese.InputMethodTips.Insert(0, $tipId)
}
if ($Remove) {
  foreach ($language in $languages) {
    while ($language.InputMethodTips.Remove($tipId)) {}
  }
}
Set-WinUserLanguageList -LanguageList $languages -Force

$updatedTips = Get-WinUserLanguageList | ForEach-Object { $_.InputMethodTips }
if ($Add -and -not ($updatedTips -contains $tipId)) {
  throw 'Windows did not retain GY in the current user keyboard list; completion will retry at the next logon.'
}

if ($Add) {
  # A competing third-party IME can register itself as the cached CTF default
  # for zh-Hans-CN (HKCU\Software\Microsoft\CTF\Assemblies\...\Default). Being
  # present in the language list does not contest that cached default, so GY
  # can stay silently shadowed in every app even though it is fully installed
  # and active. Set-WinDefaultInputMethodOverride is the documented API for
  # the same setting Windows Settings > Language > 选项 > 默认输入法 controls.
  try { Set-WinDefaultInputMethodOverride -InputTip $tipId } catch {}
}
if ($Remove) {
  try {
    $current = [string](Get-WinDefaultInputMethodOverride)
    if ($current -match '5F689D3D-73E3-4C2B-979A-2DD86E438D6F') { Set-WinDefaultInputMethodOverride }
  } catch {}
}

if ($Add) { Clear-DurableKeyboardCompletion }

function Refresh-GYInputIndicator {
  # The registered profile is visible to new applications immediately. Do not
  # force-restart ctfmon merely to refresh its icon: that process owns live
  # per-session input state and must never be disrupted by maintenance.
  Write-Verbose 'GY input indicator will refresh naturally for new applications.'
}

Refresh-GYInputIndicator
