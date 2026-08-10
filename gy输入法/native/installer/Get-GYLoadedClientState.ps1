[CmdletBinding()]
param(
  [string]$Version,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'

# A TSF DLL is loaded inside the client process. The registry can already point
# at the new version while Chrome/WeChat/Office still hold the old module in
# memory. This read-only probe makes that distinction visible without closing
# or terminating user applications.
$clients = [System.Collections.Generic.List[object]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
  try {
    foreach ($module in @($process.Modules)) {
      $path = [string]$module.FileName
      if ($path -match '\\GYInput\\tsf-(\d+\.\d+\.\d+)\\GyIme\.dll$') {
        $clients.Add([pscustomobject][ordered]@{
            processId = [int]$process.Id
            processName = [string]$process.ProcessName
            windowTitle = [string]$process.MainWindowTitle
            version = [string]$matches[1]
            modulePath = $path
          })
      }
    }
  } catch {
    # Protected/elevated processes may deny module enumeration. That is an
    # unknown result, not proof that the process is clean and not a validation
    # failure for the installation itself.
    $warnings.Add("PID $($process.Id) $($process.ProcessName): $($_.Exception.Message)")
  }
}

$result = [ordered]@{
  schemaVersion = 1
  scannedAtUtc = [DateTime]::UtcNow.ToString('o')
  expectedVersion = $Version
  clients = @($clients.ToArray())
  inaccessibleProcessCount = $warnings.Count
  warnings = @($warnings.ToArray())
}

if ($Json) {
  $result | ConvertTo-Json -Depth 5 -Compress
  exit 0
}

if ($clients.Count -eq 0) {
  Write-Host '未发现可访问进程正在加载 GY TSF DLL。' -ForegroundColor Green
} else {
  foreach ($group in @($clients | Group-Object version | Sort-Object Name)) {
    $prefix = if ($Version -and $group.Name -eq $Version) { '[通过]' } else { '[提示]' }
    $names = @($group.Group | ForEach-Object { "$($_.processName) (PID $($_.processId))" } | Sort-Object -Unique) -join ', '
    Write-Host "$prefix 已加载 GY TSF v$($group.Name)：$names" -ForegroundColor $(if ($prefix -eq '[通过]') { 'Green' } else { 'Yellow' })
  }
}
if ($warnings.Count -gt 0) {
  Write-Host "[提示] 有 $($warnings.Count) 个进程无法读取模块列表；其状态未知，不代表安装失败。" -ForegroundColor Yellow
}
exit 0
