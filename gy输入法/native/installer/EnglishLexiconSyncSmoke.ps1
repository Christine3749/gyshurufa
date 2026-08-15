param(
  [string]$SyncScriptPath = (Join-Path $PSScriptRoot 'Sync-GYEnglishLexicon.ps1'),
  [string]$ManifestUrl = 'https://example.invalid/api/ciku/ime/manifest',
  [switch]$ExpectSuccess
)

$ErrorActionPreference = 'Stop'

function Assert([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}

$isolatedLocalAppData = Join-Path $env:TEMP ('GYInput-EnglishLexiconSmoke-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $isolatedLocalAppData -Force | Out-Null
$previousLocalAppData = $env:LOCALAPPDATA
try {
  $env:LOCALAPPDATA = $isolatedLocalAppData
  # The default assertion proves an untrusted endpoint is rejected before any
  # HTTP request or activation. The opt-in local route validates the whole
  # download/hash/atomic-state transaction against a disposable Worker.
  $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $SyncScriptPath, '-ManifestUrl', $ManifestUrl)
  if ($ExpectSuccess) { $arguments += '-AllowLocalTestEndpoint' }
  & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" @arguments
  Assert ($LASTEXITCODE -eq $(if ($ExpectSuccess) { 0 } else { 2 })) $(if ($ExpectSuccess) {
    'Lexicon sync did not complete against the isolated local Worker.'
  } else {
    'Lexicon sync accepted a non-official manifest endpoint.'
  })
  $state = Join-Path $isolatedLocalAppData 'GYInput\lexicons\english-mixed\english-mixed-state.ini'
  Assert (Test-Path -LiteralPath $state -PathType Leaf) 'Lexicon sync did not record its safe failure state.'
  $content = Get-Content -LiteralPath $state -Raw
  if ($ExpectSuccess) {
    Assert ($content.Contains('status=ready')) 'Lexicon sync did not commit a ready local snapshot.'
    Assert ($content.Contains('activeVersion=2026.08.12.1')) 'Lexicon sync activated the wrong local snapshot version.'
    $snapshot = Join-Path $isolatedLocalAppData 'GYInput\lexicons\english-mixed\versions\2026.08.12.1\english.tsv'
    Assert (Test-Path -LiteralPath $snapshot -PathType Leaf) 'Lexicon sync did not persist the verified local TSV.'
  } else {
    Assert ($content.Contains('status=failed')) 'Lexicon sync did not expose a failed state for an untrusted endpoint.'
    Assert (-not $content.Contains('activeVersion=2026.')) 'Lexicon sync activated a snapshot after rejecting its endpoint.'
  }
  Write-Host 'English lexicon sync smoke passed.'
} finally {
  $env:LOCALAPPDATA = $previousLocalAppData
  if (Test-Path -LiteralPath $isolatedLocalAppData) {
    Remove-Item -LiteralPath $isolatedLocalAppData -Recurse -Force
  }
}
