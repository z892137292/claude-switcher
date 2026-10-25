# Claude 保镖 (Windows) —— 代理离线时自动关闭 Claude
# 由安装器注册为计划任务,登录时启动,隐藏窗口常驻
$ErrorActionPreference = 'SilentlyContinue'
$BASE = Join-Path $env:USERPROFILE ".claude-switcher"
$LOG = Join-Path $BASE "bodyguard.log"
New-Item -ItemType Directory -Force -Path $BASE | Out-Null

# 代理模式:优先读脚本同目录,其次读安装器写入的 proxy-mode.txt;缺失时按旧版 Clash Verge 行为
$modeFile = if ($PSScriptRoot) { Join-Path $PSScriptRoot "proxy-mode.txt" } else { '' }
if (-not $modeFile -or -not (Test-Path $modeFile)) { $modeFile = Join-Path $BASE "proxy-mode.txt" }
$PROXY_MODE = if (Test-Path $modeFile) { Get-Content $modeFile -Raw } else { '' }
if ($PROXY_MODE) { $PROXY_MODE = $PROXY_MODE.Trim() }
if (-not $PROXY_MODE) { $PROXY_MODE = 'clash-verge' }

# TUN 设备状态：地址必须属于同一张 Up 网卡；流量路径另行验证。
function Get-TunStatus {
    $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.AddressState -eq 'Preferred' })
    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')
    foreach ($nic in $adapters) {
        $assigned = @($addresses | Where-Object InterfaceIndex -eq $nic.ifIndex)
        $fake = @($assigned | Where-Object IPAddress -like '198.18.*')
        if ($assigned.Count -gt 0 -and ($fake.Count -gt 0 -or $nic.InterfaceDescription -match 'TAP|TUN|WireGuard|Wintun|VPN|Tailscale')) {
            return @{ up = $true; detail = "$($nic.Name) Up；已分配IPv4（不代表流量已走隧道）" }
        }
    }
    return @{ up = $false; detail = '未找到同时具备 Up 状态和有效IPv4的隧道网卡' }
}

# 客户端进程/服务在线判定:auto 与 other 只依赖 TUN,不要求特定进程(避免误杀)
function Test-ClientAlive {
    switch ($PROXY_MODE) {
        'clash-verge' { return [bool](Get-Process -Name 'verge-mihomo' -ErrorAction SilentlyContinue) }
        'sing-box'    { return [bool](Get-Process -Name 'sing-box' -ErrorAction SilentlyContinue) }
        'clashx'      { return [bool](Get-Process -Name 'ClashX' -ErrorAction SilentlyContinue) }
        'surge'       { return [bool](Get-Process -Name 'Surge' -ErrorAction SilentlyContinue) }
        'wireguard'   { return [bool](Get-Service -Name 'WireGuardTunnel*' -ErrorAction SilentlyContinue | Where-Object Status -eq 'Running') }
        'auto'        { return $true }
        'other'       { return $true }
        default       { return [bool](Get-Process -Name 'verge-mihomo' -ErrorAction SilentlyContinue) }
    }
}

function Get-GuardFailure {
    $tun = Get-TunStatus
    if (-not $tun.up -or -not (Test-ClientAlive)) { return '代理内核或 TUN 离线' }
    try {
        $region = Get-Content (Join-Path $BASE 'region.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $egress = Get-Egress
        $match = Test-RegionEgressMatch $egress.ip $egress.loc $region
        if (-not $match.passed) { return $match.reason }
    } catch { return '无法读取或验证出口基准' }
    return ''
}

$helper = Join-Path $PSScriptRoot 'region-functions.ps1'
if (-not (Test-Path $helper)) { throw '缺少 region-functions.ps1，请重新安装；保镖未启动' }
. $helper
. (Join-Path $PSScriptRoot 'code-functions.ps1')
$lastReason = ''
while ($true) {
    $reason = Get-GuardFailure
    if ($reason) {
        if ($reason -ne $lastReason) {
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $reason" | Out-File -Append -Encoding utf8 $LOG
        }
        try {
            if (@(Get-ManagedCodeSessions).Count -gt 0) {
                "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') 请求关闭受管理的 Claude Code 会话: $reason" | Out-File -Append -Encoding utf8 $LOG
            }
            Stop-ManagedCodeSessions
        } catch {
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Code 会话关闭未完成，请立即检查" | Out-File -Append -Encoding utf8 $LOG
        }
        $mode = try { Get-LaunchMode } catch { 'code' }
        $p = if ($mode -eq 'desktop') { Get-Process -Name 'Claude' -ErrorAction SilentlyContinue } else { $null }
        if ($p) {
            $p | Stop-Process -Force
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') 已请求关闭 Claude: $reason" | Out-File -Append -Encoding utf8 $LOG
        }
    }
    $lastReason = $reason
    Start-Sleep -Seconds 10
}
