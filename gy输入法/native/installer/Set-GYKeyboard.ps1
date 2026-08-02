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

if ($Add -and $chinese.InputMethodTips -notcontains $tipId) {
  [void]$chinese.InputMethodTips.Add($tipId)
}
if ($Remove) {
  foreach ($language in $languages) { [void]$language.InputMethodTips.Remove($tipId) }
}
Set-WinUserLanguageList -LanguageList $languages -Force
