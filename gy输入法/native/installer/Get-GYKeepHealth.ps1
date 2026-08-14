[CmdletBinding()]
param(
  [string]$KeepUrl = 'https://keep.gyenbox.com/',
  [string]$ApiBase = 'https://keep.gyenbox.com/',
  [int]$TimeoutSeconds = 8,
  [int]$RequestRetryCount = 3,
  [int]$RequestRetryDelayMs = 600,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function New-CheckResult {
  param(
    [string]$Name,
    [string]$Status,
    [string]$Message,
    [string]$Details = ''
  )
  return [ordered]@{
    name = $Name
    status = $Status # pass | warn | fail
    message = $Message
    details = $Details
  }
}

function Test-JsonVersion([string]$Value) {
  return [regex]::IsMatch($Value, '^\d+\.\d+\.\d+(-\w+)?$')
}

function Invoke-ConnectivityProbe {
  param([string]$Uri, [string]$Label)

  $attempts = @()
  for ($i = 1; $i -le $RequestRetryCount; $i++) {
    $start = Get-Date
    try {
      $builder = [System.UriBuilder]::new($Uri)
      $builder.Query = "cb=$([Guid]::NewGuid().ToString('N'))"
      $target = $builder.Uri.AbsoluteUri
      $response = Invoke-WebRequest -Uri $target -TimeoutSec $TimeoutSeconds -UseBasicParsing -Method GET
      $durMs = [Math]::Round((New-TimeSpan -Start $start -End (Get-Date)).TotalMilliseconds)
      $title = if ($response.RawContent -match '<title>([^<]+)</title>') { $matches[1] } else { '' }
      $looksKeep = if ($title -match 'GYen Keep|Gyen Keep|G[Yy]en Keep|keep') { $true } else { $false }
      return [ordered]@{
        ok = $true
        statusCode = [int]$response.StatusCode
        title = $title
        looksKeep = $looksKeep
        bodyLength = [int]($response.RawContent.Length)
        headers = @{
          location = "$($response.Headers['Location'])"
          server = "$($response.Headers['Server'])"
          cache = "$($response.Headers['CF-Cache-Status'])"
          ray = "$($response.Headers['CF-Ray'])"
          keepOrigin = "$($response.Headers['x-gyenbox-origin'])"
        }
        elapsedMs = $durMs
        attempts = $i
        sample = "$Label success in ${durMs}ms"
      }
    } catch {
      $message = $_.Exception.Message
      if ($_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode
      } else {
        $statusCode = 0
      }
      $attempts += [ordered]@{
        attempt = $i
        statusCode = $statusCode
        error = $message
        elapsedMs = [Math]::Round((New-TimeSpan -Start $start -End (Get-Date)).TotalMilliseconds)
      }
      if ($i -lt $RequestRetryCount) {
        Start-Sleep -Milliseconds $RequestRetryDelayMs
      }
    }
  }
  return [ordered]@{
    ok = $false
    statusCode = 0
    attempts = $attempts.Count
    errors = @($attempts)
    sample = "$Label failed after $($attempts.Count) tries"
  }
}

function Get-InstallState {
  $installRoot = Join-Path $env:ProgramFiles 'GYInput'
  $statePath = Join-Path $installRoot 'install-state.json'
  $result = @{
    pass = $false
    path = $statePath
    exists = $false
    version = ''
    hostVersion = ''
    state = $null
    error = ''
  }
  try {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
      $result.error = '未发现 install-state.json'
      return $result
    }
    $result.exists = $true
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $result.state = $state
    $result.version = [string]$state.coreVersion
    $result.hostVersion = [string]$state.hostVersion
    if (Test-JsonVersion $result.version -and Test-JsonVersion $result.hostVersion -and $result.version -eq $result.hostVersion) {
      $result.pass = $true
    } else {
      $result.error = "状态文件版本异常：coreVersion=$($result.version), hostVersion=$($result.hostVersion)"
    }
  } catch {
    $result.error = $_.Exception.Message
  }
  return $result
}

function Test-KeepConnectivity {
  param([string]$Version)
  $checks = [ordered]@{}
  $keepUri = $KeepUrl.TrimEnd('/')
  $checks.uri = $keepUri

  # 1) DNS 层面
  try {
    $keepHost = ([uri]$keepUri).Host
    $dns = [System.Net.Dns]::GetHostAddresses($keepHost)
    if ($dns.Count -gt 0) {
      $checks.dns = @($dns | ForEach-Object { $_.IPAddressToString })
      $checks.publicDns = @()
    } else {
      $checks.dns = @()
      $checks.publicDns = @('本机解析返回空')
    }
  } catch {
    $checks.dns = @("解析失败: $($_.Exception.Message)")
    $checks.publicDns = @()
    foreach ($server in @('1.1.1.1', '8.8.8.8', '114.114.114.114')) {
      try {
        $resolved = Resolve-DnsName -Name $keepHost -Type A -Server $server -ErrorAction Stop
        $checks.publicDns += "$server -> " + (@($resolved | ForEach-Object { $_.IPAddress } ) -join ',')
      } catch {
        $checks.publicDns += "$server -> 解析失败: $($_.Exception.Message)"
      }
    }
  }

  # 2) TCP+TLS/HTTP 层面
  $probe = Invoke-ConnectivityProbe -Uri $keepUri -Label 'keep.gyenbox.com'
  $checks.http = $probe
  $checks.versionTag = $Version

  if ($probe.ok -and $probe.statusCode -ge 200 -and $probe.statusCode -lt 400 -and $probe.looksKeep) {
    $checks.status = 'pass'
    $checks.summary = "HTTP 可达，状态码 $($probe.statusCode)，耗时 $($probe.elapsedMs)ms"
    $checks.origin = $probe.headers.keepOrigin
    return New-CheckResult 'keep-connectivity' 'pass' $checks.summary ($checks | ConvertTo-Json -Depth 5 -Compress)
  }
  if ($probe.ok -and $probe.statusCode -ge 200 -and $probe.statusCode -lt 400 -and -not $probe.looksKeep) {
    $checks.status = 'warn'
    $checks.summary = "Keep 返回 HTML 非预期（title: '$($probe.title)'），可能为被代理重定向页面"
    return New-CheckResult 'keep-connectivity' 'warn' $checks.summary ($checks | ConvertTo-Json -Depth 5 -Compress)
  }

  # 3) API 层面（如果 DNS/TCP OK，也许只是前端被拦截）
  if ($checks.dns.Count -gt 0 -and -not ($checks.dns[0] -like '解析失败*')) {
    $apiProbe = Invoke-ConnectivityProbe -Uri ($ApiBase.TrimEnd('/') + '/api/health') -Label 'keep.gyenbox.com/api/health'
    $checks.apiHealth = $apiProbe
    if ($apiProbe.ok -and $apiProbe.statusCode -ge 200 -and $apiProbe.statusCode -lt 400) {
      $checks.status = 'warn'
      $checks.summary = 'Keep 主站可达但 /api/health 不可达（可能是代理/路由层问题）'
      return New-CheckResult 'keep-connectivity' 'warn' $checks.summary ($checks | ConvertTo-Json -Depth 5 -Compress)
    }
  }

  $checks.status = 'fail'
  $checks.summary = 'Keep 访问路径不可达'
  return New-CheckResult 'keep-connectivity' 'fail' $checks.summary ($checks | ConvertTo-Json -Depth 5 -Compress)
}

function Get-ClientClients {
  param([string]$ExpectedVersion)
  try {
    $installedScript = Join-Path $PSScriptRoot 'Get-GYLoadedClientState.ps1'
    if (Test-Path -LiteralPath $installedScript -PathType Leaf) {
      $json = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installedScript -Version $ExpectedVersion -Json
      return $json | ConvertFrom-Json
    }
    return $null
  } catch {
    return $null
  }
}

$state = Get-InstallState
$checks = [ordered]@{}
$issues = @()

if ($state.exists -and $state.pass) {
  $checks.installState = New-CheckResult 'install-state' 'pass' "install-state.json 可用，当前版本 $($state.version)"
} elseif ($state.exists) {
  $checks.installState = New-CheckResult 'install-state' 'warn' "install-state.json 存在但版本字段异常" $state.error
  $issues += 'install-state'
} else {
  $checks.installState = New-CheckResult 'install-state' 'fail' "install-state.json 缺失：$($state.error)"
  $issues += 'install-state'
}

$keepCheck = Test-KeepConnectivity -Version $state.version
$checks.keepConnectivity = $keepCheck
if ($keepCheck.status -eq 'fail') { $issues += 'keep-connectivity' }

$loaded = Get-ClientClients -ExpectedVersion $state.version
if ($loaded -and $loaded.clients) {
  $extra = $loaded.clients | Where-Object { $_.version -ne $state.version }
  if ($extra.Count -gt 0) {
    $checks.loadedProcesses = New-CheckResult 'loaded-processes' 'warn' "检测到旧版 TSF 进程 $($extra.Count) 个，建议重启应用或调用 Repair。"
    $issues += 'loaded-processes'
  } else {
    $checks.loadedProcesses = New-CheckResult 'loaded-processes' 'pass' '运行进程加载版本与当前一致。'
  }
  $checks.loadedProcesses.counts = $loaded.clients.Count
} else {
  $checks.loadedProcesses = New-CheckResult 'loaded-processes' 'pass' '未发现持有 GY TSF DLL 的活跃进程，或该进程列表不可访问。'
  $checks.loadedProcesses.counts = 0
}

$overall = 'pass'
if ($issues.Count -gt 0) { $overall = if ($issues -contains 'install-state' -or $issues -contains 'keep-connectivity') { 'fail' } else { 'warn' } }

$result = [ordered]@{
  schemaVersion = 1
  generatedAtUtc = [DateTime]::UtcNow.ToString('o')
  overall = $overall
  installVersion = $state.version
  installedBy = 'Get-GYKeepHealth.ps1'
  checks = $checks
}

$result['issues'] = @($issues)
  $result['recommendations'] = @(
  if ($overall -eq 'fail') {
    @(
      '先确认本机网络可访问 keep.gyenbox.com（443/tcp 未被策略封禁）',
      '若你在公司内网，先切换到可访问外网网络或开启可信任代理',
      '随后执行 Start-Process -FilePath ".../Repair-GYInput.ps1" -Verb RunAs -PassThru'
    )
  } else {
    @(
      '网络与版本安装态一致，若同步仍异常请执行 GY Keep 应用端登录态重刷并再次重启客户端'
    )
  }
)

if ($Json) {
  $result | ConvertTo-Json -Depth 12 -Compress
  exit 0
}

Write-Host ("[健康体检] overall={0}" -f $result.overall)
Write-Host ("install-state: {0}" -f $checks['installState'].status)
Write-Host ("keep-connectivity: {0} -> {1}" -f $checks['keepConnectivity'].status, $checks['keepConnectivity'].message)
Write-Host ("loaded-processes: {0}" -f $checks['loadedProcesses'].status)
if ($result.issues.Count -gt 0) {
  Write-Host ('建议：' + ($result.recommendations -join '; '))
}
exit 0
