[CmdletBinding()]
param(
  [string]$ImeSource = '',
  [string]$CapturePolicy = '',
  [string]$PresentationPolicy = '',
  [string]$CandidateWindow = ''
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ImeSource) { $ImeSource = Join-Path $scriptRoot '..\src\GyIme.cpp' }
if (-not $CapturePolicy) { $CapturePolicy = Join-Path $scriptRoot '..\src\InputCapturePolicy.h' }
if (-not $PresentationPolicy) { $PresentationPolicy = Join-Path $scriptRoot '..\src\CandidatePresentationPolicy.h' }
if (-not $CandidateWindow) { $CandidateWindow = Join-Path $scriptRoot '..\src\CandidateWindow.cpp' }

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
  if (-not $Text.Contains($Needle)) { throw $Message }
}

$ime = Get-Content -LiteralPath $ImeSource -Raw
$capture = Get-Content -LiteralPath $CapturePolicy -Raw
$presentation = Get-Content -LiteralPath $PresentationPolicy -Raw
$window = Get-Content -LiteralPath $CandidateWindow -Raw

Assert-Contains $ime "key >= '0' && key <= '9'" 'EN digit input path is missing.'
Assert-Contains $ime 'Digits are literal text in EN' 'EN digit contract is not documented at the implementation boundary.'
Assert-Contains $ime "action.trailing_character = L' '" 'EN Space no longer submits literal input plus a space.'
Assert-Contains $ime 'ShouldCommitRawBeforeBoundary' 'EN punctuation can implicitly accept a completion.'
Assert-Contains $capture 'EN has a bounded explicit list, never Chinese paging' 'EN list is not separated from Chinese paging.'
Assert-Contains $presentation 'return purpose == Purpose::ChineseConversion' 'English candidate expansion is not structurally excluded.'
Assert-Contains $presentation 'EnglishList' 'The bounded English expanded list is missing.'
Assert-Contains $presentation 'constexpr bool UsesNumericShortcuts' 'Numeric shortcut policy is missing.'
Assert-Contains $window 'kEnglishCandidateGap = 8' 'English candidate spacing regressed.'
Assert-Contains $window 'kEnglishTextOverhangGuard = 3' 'Final Latin glyph clipping protection regressed.'

Write-Host 'English interaction policy smoke: PASS'
