param(
  [switch]$Add,
  [switch]$Remove
)

$ErrorActionPreference = 'Stop'
if ($Add -eq $Remove) { throw 'Specify exactly one of -Add or -Remove.' }

$tipId = '0804:{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}{5F689D3E-73E3-4C2B-979A-2DD86E438D6F}'
$languages = Get-WinUserLanguageList
$chinese = $languages | Where-Object LanguageTag -eq 'zh-Hans-CN' | Select-Object -First 1
if (-not $chinese) { throw 'Simplified Chinese (China) is not installed. Add it in Windows Settings first.' }

if ($Add) {
  if ($chinese.InputMethodTips -contains $tipId) { [void]$chinese.InputMethodTips.Remove($tipId) }
  # Insert at the front, not appended: Windows treats a language's first tip
  # as its preferred one, and a competing IME (e.g. Tencent WeType) installed
  # either before or after GY would otherwise keep that position indefinitely.
  $chinese.InputMethodTips.Insert(0, $tipId)
}
if ($Remove) {
  foreach ($language in $languages) { [void]$language.InputMethodTips.Remove($tipId) }
}
Set-WinUserLanguageList -LanguageList $languages -Force

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
