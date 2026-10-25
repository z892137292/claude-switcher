# Claude 账号切换器 - Windows 核心脚本
# 用法: powershell -NoProfile -File claude-switch.ps1 check|status|switch A|B|checkdetail|fix
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# ============ 安装时可配置项(安装器自动改写) ============
$PROXY_MODE = "clash-verge"            # 代理客户端: clash-verge|sing-box|clashx|surge|wireguard|other|auto
$COUNTRY_TARGET = "US"                 # 目标出口国家(安装时按出口自动识别)
$TZ_TARGET = "Eastern Standard Time"   # Windows 时区ID
$PROXY_GROUP = "GLOBAL"                # Clash 代理组名
# =======================================================

$BASE = Join-Path $env:USERPROFILE ".claude-switcher"
$DATA = Join-Path $env:APPDATA "Claude"
$LOG  = Join-Path $BASE "claude-switch.log"
$REGION_FILE = Join-Path $BASE "region.json"
. (Join-Path $PSScriptRoot "region-functions.ps1")
$CLASH_DIR = @(
    (Join-Path $env:APPDATA "io.github.clash-verge-rev.clash-verge-rev"),
    (Join-Path $env:LOCALAPPDATA "io.github.clash-verge-rev.clash-verge-rev")
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $CLASH_DIR) { $CLASH_DIR = Join-Path $env:APPDATA "io.github.clash-verge-rev.clash-verge-rev" }
New-Item -ItemType Directory -Force -Path "$BASE\accounts" | Out-Null
$regionConfig = if (Test-Path $REGION_FILE) { try { Get-Content $REGION_FILE -Raw | ConvertFrom-Json } catch { $null } } else { $null }
$COUNTRY_TARGET = if ($regionConfig.country) { [string]$regionConfig.country } else { $COUNTRY_TARGET }
$TZ_TARGET = if ($regionConfig.tz_windows) { [string]$regionConfig.tz_windows } else { $TZ_TARGET }
$CULTURE_TARGET = if ($regionConfig.culture) { [string]$regionConfig.culture } else { 'en-US' }

function Log($m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" | Out-File -Append -Encoding utf8 $LOG }

# 代理客户端显示名(供检查细节输出)
function Get-ProxyName {
    switch ($PROXY_MODE) {
        'clash-verge' { return 'Clash Verge' }
        'sing-box'    { return 'sing-box' }
        'clashx'      { return 'ClashX' }
        'surge'       { return 'Surge' }
        'wireguard'   { return 'WireGuard' }
        'other'       { return '其他代理客户端' }
        'auto'        { return '代理客户端(auto)' }
        default       { return $PROXY_MODE }
    }
}

# 代理客户端在线判定:按安装时识别的客户端分派;auto 任一命中即活,other 只依赖 TUN
function Test-ProxyAlive {
    switch ($PROXY_MODE) {
        'clash-verge' { return [bool](Get-Process -Name 'verge-mihomo' -ErrorAction SilentlyContinue) }
        'sing-box'    { return [bool](Get-Process -Name 'sing-box' -ErrorAction SilentlyContinue) }
        'clashx'      { return [bool](Get-Process -Name 'ClashX' -ErrorAction SilentlyContinue) }
        'surge'       { return [bool](Get-Process -Name 'Surge' -ErrorAction SilentlyContinue) }
        'wireguard'   { return [bool](Get-Service -Name 'WireGuardTunnel*' -ErrorAction SilentlyContinue | Where-Object Status -eq 'Running') }
        'other'       { return $true }
        'auto' {
            if (Get-Process -Name 'verge-mihomo','sing-box','ClashX','Surge' -ErrorAction SilentlyContinue) { return $true }
            return [bool](Get-Service -Name 'WireGuardTunnel*' -ErrorAction SilentlyContinue | Where-Object Status -eq 'Running')
        }
        default { return [bool](Get-Process -Name 'verge-mihomo' -ErrorAction SilentlyContinue) }
    }
}

# TUN 在线判定:198.18 假IP段优先,否则回退到任意 Up 状态的虚拟网卡(兼容 Astrill/WireGuard/OpenVPN 等)
function Get-TunStatus {
    if (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like '198.18.*' }) {
        return @{ up = $true; detail = '198.18 假IP段' }
    }
    $nic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and ($_.InterfaceDescription -match 'TAP|TUN|WireGuard|Wintun|VPN|Tailscale') }
    if ($nic) { return @{ up = $true; detail = '通用虚拟网卡' } }
    return @{ up = $false; detail = '不在线' }
}
function Test-TunUp {
    $t = Get-TunStatus
    return [bool]$t.up
}

# STUN 探针(纯 .NET UDP,手工构造 RFC5389 报文)
function Get-StunPublicIP([string]$server, [int]$port, [int]$timeoutMs = 2000) {
    try { $addr = ([System.Net.Dns]::GetHostAddresses($server) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1) } catch { return $null }
    if (-not $addr) { return $null }
    $udp = New-Object System.Net.Sockets.UdpClient
    $udp.Client.ReceiveTimeout = $timeoutMs
    try {
        $txn = New-Object byte[] 12; (New-Object Random).NextBytes($txn)
        $req = [byte[]](0x00, 0x01, 0x00, 0x00) + [byte[]](0x21, 0x12, 0xA4, 0x42) + $txn
        $udp.Connect($addr, $port)
        [void]$udp.Send($req, $req.Length)
        $remote = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $resp = $udp.Receive([ref]$remote)
        $pos = 20
        while ($pos + 4 -le $resp.Length) {
            $atype = ([int]$resp[$pos] -shl 8) -bor $resp[$pos + 1]
            $alen  = ([int]$resp[$pos + 2] -shl 8) -bor $resp[$pos + 3]
            if (($atype -eq 0x20 -or $atype -eq 0x01) -and $alen -ge 8 -and $resp[$pos + 5] -eq 0x01) {
                $ipBytes = @($resp[$pos + 8], $resp[$pos + 9], $resp[$pos + 10], $resp[$pos + 11])
                if ($atype -eq 0x20) {
                    $cookie = [byte[]](0x21, 0x12, 0xA4, 0x42)
                    for ($i = 0; $i -lt 4; $i++) { $ipBytes[$i] = $ipBytes[$i] -bxor $cookie[$i] }
                }
                return ($ipBytes -join '.')
            }
            $pos += 4 + $alen + ((4 - ($alen % 4)) % 4)
        }
    } catch { return $null } finally { $udp.Close() }
    return $null
}

function Test-WebRTC($exitIp) {
    $servers = @(@("stun.miwifi.com", 3478), @("stun.chat.bilibili.com", 3478), @("stun.l.google.com", 19302), @("stun.cloudflare.com", 3478))
    $found = @()
    foreach ($s in $servers) {
        $r = Get-StunPublicIP $s[0] $s[1]
        if ($r -and ($found -notcontains $r)) { $found += $r }
    }
    if ($found.Count -eq 0) { return @{ code = 'warn'; detail = 'STUN无响应，未观察到候选地址，无法证明UDP无泄漏' } }
    $leak = $found | Where-Object { $_ -ne $exitIp }
    if ($leak) { return @{ code = 'fail'; detail = "暴露非代理IP: $(($leak | ForEach-Object { Protect-ExitIp $_ }) -join ',')" } }
    return @{ code = 'ok'; detail = '仅暴露代理IP' }
}

function Test-RulesPinned {
    if (-not $PROXY_GROUP -or $PROXY_GROUP -match '^(DIRECT|REJECT|REJECT-DROP|PASS)$') { return $false }
    $paths = @((Join-Path (Join-Path $CLASH_DIR 'profiles') 'Merge.yaml'), (Join-Path $CLASH_DIR 'clash-verge.yaml')) | Where-Object { Test-Path $_ }
    $expected = @('DOMAIN-SUFFIX,claude.ai', 'DOMAIN-SUFFIX,anthropic.com', 'DST-PORT,3478', 'DST-PORT,5349', 'DST-PORT,19302')
    foreach ($path in $paths) {
        $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
        $allPresent = $true
        foreach ($rule in $expected) {
            # Match a complete YAML list item; comments, DIRECT and prefix matches do not count.
            $pattern = '^\s*-\s*[' + "'" + '"]?' + [regex]::Escape("$rule,$PROXY_GROUP") + '[' + "'" + '"]?\s*(?:#.*)?$'
            if (-not ($lines | Where-Object { $_ -cmatch $pattern })) { $allPresent = $false; break }
        }
        if ($allPresent) { return $true }
    }
    return $false
}

function Invoke-SetRegion([switch]$Confirmed) {
    $region = Get-RegionInfo
    if (-not $region.country -or -not $region.ip) { "FAIL:无法获取出口IP或国家，请检查网络后重试"; return }
    if ($region.country -eq 'CN' -and $env:FORCE -ne '1') { "FAIL:出口国家为 CN，请先开启代理；如确需跳过，请设置 FORCE=1"; return }
    if (-not $region.tz_windows) {
        $region.tz_windows = (Get-TimeZone).Id
        "WARN:无法识别出口时区 $($region.tz_iana)，保留当前时区 $($region.tz_windows)"
    }
    if (Get-Process -Name 'Claude' -ErrorAction SilentlyContinue) {
        "FAIL:请先完全退出 Claude，再重新锁定出口环境"; return
    }
    if (-not $Confirmed) {
        if ([Console]::IsInputRedirected) { "FAIL:非交互场景必须显式指定 --confirm"; return }
        if ((Read-Host '确认将当前出口保存为新基准？请输入 YES') -cne 'YES') { "FAIL:已取消重新锁定环境"; return }
    }
    $oldRegion = if (Test-Path $REGION_FILE) { try { Get-Content $REGION_FILE -Raw | ConvertFrom-Json } catch { $null } } else { $null }
    $region.exit_ip = $region.ip
    $region | Add-Member -NotePropertyName locked_at -NotePropertyValue (Get-Date).ToString('o') -Force
    New-Item -ItemType Directory -Force -Path $BASE | Out-Null
    Save-RegionInfo $region $REGION_FILE
    Apply-RegionUserSettings $region | Out-Null
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Apply-RegionSystemSettings $region | ForEach-Object { "REGION:$_" }
    } else {
        $adminScript = Join-Path $BASE 'apply-region-admin.ps1'
        $helperPath = (Join-Path $PSScriptRoot 'region-functions.ps1').Replace("'", "''")
        $regionPath = $REGION_FILE.Replace("'", "''")
        $adminBody = @"
. '$helperPath'
`$r = Get-Content '$regionPath' -Raw | ConvertFrom-Json
Apply-RegionSystemSettings `$r
"@
        $utf8Bom = New-Object System.Text.UTF8Encoding -ArgumentList $true
        [System.IO.File]::WriteAllText($adminScript, $adminBody, $utf8Bom)
        try {
            Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$adminScript`""
            "REGION:已请求管理员权限应用系统时区/区域设置"
        } catch { "WARN:管理员授权被取消，系统时区和系统区域设置未应用" }
    }
    $oldCountry = if ($oldRegion.country) { $oldRegion.country } else { '无' }
    $oldIp = if ($oldRegion.exit_ip) { Protect-ExitIp $oldRegion.exit_ip } else { '无' }
    $newIp = Protect-ExitIp $region.exit_ip
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') country=$oldCountry -> $($region.country); exit_ip=$oldIp -> $newIp" |
        Out-File -Append -Encoding utf8 (Join-Path $BASE 'region-change.log')
    "OK:已同步 $($region.country) / $($region.tz_iana) / $($region.culture)"
}

function Invoke-CheckDetail {
    $pname = Get-ProxyName
    if (Test-ProxyAlive) {
        if ($PROXY_MODE -eq 'other') { "代理内核=ok:$pname(仅校验TUN)" }
        else { "代理内核=ok:$pname 运行中" }
    } else { "代理内核=fail:$pname 未运行" }

    $tun = Get-TunStatus
    if ($tun.up) {
        if ($tun.detail -eq '198.18 假IP段') { "TUN网卡=ok" }
        else { "TUN网卡=ok:$($tun.detail)" }
    } else { "TUN网卡=fail:不在线" }

    $e = Get-Egress
    $region = if (Test-Path $REGION_FILE) { try { Get-Content $REGION_FILE -Raw | ConvertFrom-Json } catch { $null } } else { $null }
    $targetCountry = if ($region.country) { ([string]$region.country).ToUpperInvariant() } else { '' }
    if (-not $region -or -not $e.ip -or -not $e.loc) { "出口IP=fail:无法获取出口IP/国家或缺少锁定基准" }
    elseif ($e.loc -eq $targetCountry) { "出口IP=ok:国家 $($e.loc)" }
    else { "出口IP=fail:当前国家 $($e.loc)，期望 $targetCountry" }

    $egressMatch = Test-RegionEgressMatch $e.ip $e.loc $region
    if ($egressMatch.passed) { "IP一致=ok:出口IP与锁定基准完全一致" }
    else { "IP一致=fail:$($egressMatch.reason)" }

    $tz = (Get-TimeZone).Id
    $targetTz = if ($region.tz_windows) { $region.tz_windows } else { $TZ_TARGET }
    if ($tz -eq $targetTz) { "时区=ok:$tz" } else { "时区=fail:$tz(期望$targetTz)" }

    $cult = (Get-Culture).Name
    $targetCulture = if ($region.culture) { $region.culture } else { $CULTURE_TARGET }
    if ($cult -eq $targetCulture) { "地区=ok:$cult" } else { "地区=fail:$cult(期望$targetCulture)" }

    $v6off = [bool](Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true })
    if (-not $v6off) { "IPv6=ok:已关闭" } else { "IPv6=fail:未关闭" }

    $dns = (Resolve-DnsName claude.ai -Type A -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
    if ($dns -like '198.18.*') { "DNS=ok:走隧道" } else { "DNS=fail:未走隧道($dns)" }

    $w = Test-WebRTC $e.ip
    "WebRTC=$($w.code):$($w.detail)"

    $bg = Get-ScheduledTask -TaskName 'ClaudeBodyguard' -ErrorAction SilentlyContinue
    if ($bg -and $bg.State -eq 'Running') { "保镖=ok:运行中" } else { "保镖=fail:未运行，请修复或重新安装" }

    if (Test-RulesPinned) { "规则置顶=ok:所需规则已配置(静态检查)" } else { "规则置顶=fail:未生效" }

    # 客户端语言: Windows 端 Claude 跟随系统区域格式,地区检查已覆盖
    "客户端语言=ok:跟随系统"

    $asn = if ($region.asn) { [string]$region.asn } else { '未记录' }
    "ASN属性=info:$asn (仅记录，不阻断)"

    $r1 = & curl.exe -s --max-time 8 -o NUL -w '%{http_code}' "https://claude.ai/" 2>$null
    $r2 = & curl.exe -s --max-time 8 -o NUL -w '%{http_code}' "https://api.anthropic.com/v1/models" 2>$null
    if ($r1 -match '^[23][0-9]{2}$' -and $r2 -match '^(2[0-9]{2}|401)$') { "生态可达性=ok:网页:$r1 API:$r2 (无认证探测，不代表账号可用)" }
    else { "生态可达性=fail:网页:$r1 API:$r2 (访问受限、服务错误或传输失败)" }
}

function Invoke-Fix {
    "FIX:开始一键修复"

    # A. 拉起代理客户端并等待内核+TUN(仅 Clash Verge 可自动拉起)
    if ($PROXY_MODE -eq 'clash-verge') {
        if (-not (Test-ProxyAlive)) {
            "FIX:正在启动 Clash Verge..."
            $cv = Get-ChildItem "$env:LOCALAPPDATA\Programs","$env:ProgramFiles","${env:ProgramFiles(x86)}" -Recurse -Filter "Clash Verge*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cv) { Start-Process $cv.FullName } else { "FIX:未找到 Clash Verge 可执行文件,请手动启动" }
        }
        $ok = $false
        for ($i = 0; $i -lt 40; $i++) { if ((Test-ProxyAlive) -and (Test-TunUp)) { $ok = $true; break }; Start-Sleep 1 }
        if ($ok) { "FIX:代理内核+TUN ✓" } else { "FIX:代理内核/TUN ✗(请打开 Clash Verge 检查节点/线路及 TUN 开关)" }
    } else {
        $pname = Get-ProxyName
        if ((Test-ProxyAlive) -and (Test-TunUp)) { "FIX:代理客户端($pname)+TUN ✓" }
        elseif (-not (Test-ProxyAlive)) { "FIX:代理客户端($pname)未运行,请手动启动并开启 TUN 模式" }
        else { "FIX:TUN 未在线($pname),请检查客户端 TUN 开关" }
    }

    # B. 时区/IPv6/DNS/保镖(需管理员:通过 UAC 弹一次)
    $adminScript = @()
    $targetZone = if ($regionConfig.tz_windows) { [string]$regionConfig.tz_windows } else { $TZ_TARGET }
    $targetCulture = if ($regionConfig.culture) { [string]$regionConfig.culture } else { $CULTURE_TARGET }
    if ((Get-TimeZone).Id -ne $targetZone) { $adminScript += "Set-TimeZone -Id '$targetZone'" }
    if ((Get-Culture).Name -ne $targetCulture) {
        try { Set-Culture -CultureInfo $targetCulture -ErrorAction Stop; "FIX:地区格式($targetCulture) ✓" }
        catch { "FIX:地区格式($targetCulture) ✗：$($_.Exception.Message)" }
    }
    $adminScript += ". '$PSScriptRoot\region-functions.ps1'; `$region = Get-Content '$REGION_FILE' -Raw | ConvertFrom-Json; Apply-RegionSystemSettings `$region | Out-Null"
    if (Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue | Where-Object { $_.Enabled }) { $adminScript += "Get-NetAdapter -Physical | Get-NetAdapterBinding -ComponentID ms_tcpip6 | Disable-NetAdapterBinding -Confirm:`$false" }
    $adminScript += "Clear-DnsClientCache"
    if (-not (Get-ScheduledTask -TaskName 'ClaudeBodyguard' -ErrorAction SilentlyContinue)) {
        $adminScript += "`$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$BASE\claude-bodyguard.ps1`"'; `$t = New-ScheduledTaskTrigger -AtLogOn; Register-ScheduledTask -TaskName 'ClaudeBodyguard' -Action `$a -Trigger `$t -Force | Out-Null; Start-ScheduledTask -TaskName 'ClaudeBodyguard'"
    }
    if ($adminScript.Count -gt 0) {
        "FIX:修复时区/IPv6/DNS/保镖(需要管理员授权)..."
        $tmp = "$env:TEMP\claude-fix-$([guid]::NewGuid().Guid).ps1"
        (@("`$ErrorActionPreference = 'Stop'") + $adminScript) -join "`n" | Out-File -Encoding utf8 $tmp
        try {
            $repair = Start-Process powershell -Verb RunAs -Wait -PassThru -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tmp`""
            if ($repair.ExitCode -eq 0) { "FIX:系统修复命令已执行，请以重新检查结果为准" }
            else { "FAIL:系统修复失败(退出码=$($repair.ExitCode))，请重新检查" }
        } catch { "FAIL:管理员授权被取消或系统修复未执行" }
        finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
    } else {
        "FIX:时区/IPv6/保镖 无需修复 ✓"
    }

    # B2. 置顶规则(仅 Clash Verge 可自动改写)
    if ($PROXY_MODE -ne 'clash-verge') {
        "FIX:请在 $(Get-ProxyName) 中自行添加 Claude 域名置顶规则"
    } elseif (-not (Test-RulesPinned)) {
        "FIX:重写置顶规则..."
        $merge = @"
profile:
  store-selected: true

prepend-rules:
  - DOMAIN-SUFFIX,claude.ai,$PROXY_GROUP
  - DOMAIN-SUFFIX,claude.com,$PROXY_GROUP
  - DOMAIN-SUFFIX,anthropic.com,$PROXY_GROUP
  - DOMAIN-SUFFIX,claudeusercontent.com,$PROXY_GROUP
  - DOMAIN-SUFFIX,challenges.cloudflare.com,$PROXY_GROUP
  - DOMAIN-SUFFIX,datadoghq.com,$PROXY_GROUP
  - DOMAIN-SUFFIX,segment.io,$PROXY_GROUP
  - DOMAIN-SUFFIX,stripe.com,$PROXY_GROUP
  - DOMAIN-SUFFIX,stripe.network,$PROXY_GROUP
  - DOMAIN-SUFFIX,stripecdn.com,$PROXY_GROUP
  - DOMAIN-SUFFIX,intercom.io,$PROXY_GROUP
  - DOMAIN-SUFFIX,intercomcdn.com,$PROXY_GROUP
  - DOMAIN-SUFFIX,intercomassets.com,$PROXY_GROUP
  - DST-PORT,3478,$PROXY_GROUP
  - DST-PORT,5349,$PROXY_GROUP
  - DST-PORT,19302,$PROXY_GROUP
"@
        New-Item -ItemType Directory -Force -Path "$CLASH_DIR\profiles" | Out-Null
        $merge | Out-File -Encoding utf8 "$CLASH_DIR\profiles\Merge.yaml"
        Get-Process -Name 'clash-verge','Clash Verge' -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep 2
        $cv = Get-ChildItem "$env:LOCALAPPDATA\Programs" -Recurse -Filter "Clash Verge*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cv) { Start-Process $cv.FullName }
        for ($i = 0; $i -lt 40; $i++) { if (Test-TunUp) { break }; Start-Sleep 1 }
        if (Test-RulesPinned) { "FIX:置顶规则 ✓" } else { "FIX:置顶规则 ✗(请重启 Clash Verge)" }
    }

    # C. 出口IP最终验证
    Start-Sleep 2
    $e = Get-Egress
    $match = Test-RegionEgressMatch $e.ip $e.loc $regionConfig
    if ($match.passed) { "FIX:出口与锁定基准一致 ✓" } else { "FAIL:$($match.reason)；修复不会改写基准" }
    "FIX:修复流程结束"
}

function Invoke-Status {
    $cur = if (Test-Path "$BASE\current.txt") { (Get-Content "$BASE\current.txt" -Raw).Trim() } else { 'none' }
    $hasA = if (Test-Path "$BASE\accounts\A") { 1 } else { 0 }
    $hasB = if (Test-Path "$BASE\accounts\B") { 1 } else { 0 }
    "current=$cur hasA=$hasA hasB=$hasB"
}

function Stop-ClaudeApp {
    $p = Get-Process -Name 'Claude' -ErrorAction SilentlyContinue
    if (-not $p) { return $true }
    $p | Stop-Process -Force
    for ($i = 0; $i -lt 15; $i++) { if (-not (Get-Process -Name 'Claude' -ErrorAction SilentlyContinue)) { return $true }; Start-Sleep 1 }
    return $false
}

function Save-Account($name) {
    $dest = Join-Path "$BASE\accounts" $name
    $stage = "$dest.new"
    $previous = "$dest.previous"
    if ((Test-Path $stage) -or (Test-Path $previous)) {
        throw "账号$name 存在待恢复快照($stage 或 $previous)，请先确认数据后手动处理"
    }
    if (-not (Test-Path $DATA)) { throw "当前 Claude 数据目录不存在，无法归档账号$name" }
    robocopy "$DATA" "$stage" /MIR /NFL /NDL /NJH /NJS | Out-Null
    $copyCode = $LASTEXITCODE
    if ($copyCode -ge 8 -or -not (Test-Path $stage)) {
        throw "账号$name 归档失败(robocopy=$copyCode)，原数据未删除"
    }
    $hadPrevious = Test-Path $dest
    try {
        if ($hadPrevious) { Move-Item -LiteralPath $dest -Destination $previous -ErrorAction Stop }
        Move-Item -LiteralPath $stage -Destination $dest -ErrorAction Stop
    } catch {
        if ((Test-Path $previous) -and -not (Test-Path $dest)) { Move-Item -LiteralPath $previous -Destination $dest -ErrorAction SilentlyContinue }
        throw "账号$name 快照替换失败: $($_.Exception.Message)"
    }
    Log "已存档账号$name (robocopy=$copyCode)"
}

function Start-ClaudeApp {
    $locked = try { Get-Content $REGION_FILE -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $null }
    $now = Get-Egress
    $match = Test-RegionEgressMatch $now.ip $now.loc $locked
    if (-not $match.passed) { throw "启动前出口检查失败：$($match.reason)" }
    if (-not (Test-ProxyAlive) -or -not (Test-TunUp)) { throw '启动前代理内核或TUN检查失败' }
    $exe = @("$env:LOCALAPPDATA\AnthropicClaude\Claude.exe", "$env:LOCALAPPDATA\Programs\Claude\Claude.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($exe) { Start-Process $exe -ErrorAction Stop }
    else {
        $app = Get-StartApps | Where-Object { $_.Name -eq 'Claude' } | Select-Object -First 1
        if (-not $app.AppID) { throw '未找到 Claude 应用，请先安装 Claude 桌面版' }
        Start-Process "shell:AppsFolder\$($app.AppID)" -ErrorAction Stop
    }
}

function Invoke-Switch($target) {
    if ($target -notin @('A','B')) { "FAIL:目标账号必须是 A 或 B"; return }
    $targetArchive = "$BASE\accounts\$target"
    if ((Test-Path "$targetArchive.new") -or ((Test-Path "$targetArchive.previous") -and -not (Test-Path $targetArchive))) {
        "FAIL:账号$target 存在待恢复快照(.new/.previous)，请先确认并手动处理"; return
    }
    if ((Test-Path "$DATA.new") -or (Test-Path "$DATA.previous")) {
        "FAIL:发现残留 Claude 数据目录(.new/.previous)，请先确认并手动处理"; return
    }
    $checkLines = @(Invoke-CheckDetail)
    $checkResult = Test-CheckReport $checkLines
    if (-not $checkResult.passed) {
        "FAIL:安全检查未通过，已阻止启动 Claude：$($checkResult.errors -join '; ')"
        return
    }
    $cur = if (Test-Path "$BASE\current.txt") { (Get-Content "$BASE\current.txt" -Raw).Trim() } else { 'none' }
    $enrolledNow = $false

    # 首次运行:收编当前登录为账号A
    if ($cur -eq 'none' -and (Test-Path $DATA) -and (Get-ChildItem $DATA -ErrorAction SilentlyContinue)) {
        if (-not (Stop-ClaudeApp)) { "FAIL:Claude 未能退出，请手动退出后重试"; return }
        try { Save-Account A } catch { "FAIL:$($_.Exception.Message)"; return }
        $cur = 'A'; 'A' | Out-File -Encoding ascii -NoNewline "$BASE\current.txt"
        $enrolledNow = $true
        Log "首次运行:当前登录状态已收编为账号A"
        "NOTE:已将当前登录收编为账号A"
    }

    if ($cur -eq $target) {
        if ($enrolledNow) { Remove-Item "$BASE\accounts\$target.previous" -Recurse -Force -ErrorAction SilentlyContinue }
        Start-ClaudeApp; "INFO:当前已是账号$target"; return
    }

    if (-not (Stop-ClaudeApp)) { "FAIL:Claude 未能退出，请手动退出后重试"; return }

    if ($cur -ne 'none' -and (Test-Path $DATA) -and -not $enrolledNow) {
        try { Save-Account $cur } catch { "FAIL:$($_.Exception.Message)"; return }
    }

    if (Test-Path "$BASE\accounts\$target") {
        $dataStage = "$DATA.new"
        if (Test-Path $dataStage) { "FAIL:发现残留数据目录 $dataStage，请确认后手动处理"; return }
        robocopy "$targetArchive" "$dataStage" /E /NFL /NDL /NJH /NJS | Out-Null
        $restoreCode = $LASTEXITCODE
        if ($restoreCode -ge 8 -or -not (Test-Path $dataStage)) {
            Remove-Item $dataStage -Recurse -Force -ErrorAction SilentlyContinue
            "FAIL:账号$target 恢复失败(robocopy=$restoreCode)，当前数据未覆盖"; return
        }
        $dataPrevious = "$DATA.previous"
        if (Test-Path $dataPrevious) { "FAIL:发现残留数据目录 $dataPrevious，请确认后手动处理"; return }
        try {
            if (Test-Path $DATA) { Move-Item -LiteralPath $DATA -Destination $dataPrevious -ErrorAction Stop }
            Move-Item -LiteralPath $dataStage -Destination $DATA -ErrorAction Stop
        }
        catch {
            if ((Test-Path $dataPrevious) -and -not (Test-Path $DATA)) { Move-Item -LiteralPath $dataPrevious -Destination $DATA -ErrorAction SilentlyContinue }
            "FAIL:账号$target 原子替换失败: $($_.Exception.Message)"; return
        }
        Remove-Item $dataPrevious -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$targetArchive.previous" -Recurse -Force -ErrorAction SilentlyContinue
        Log "已载入账号$target 存档"
    } else {
        $dataPrevious = "$DATA.previous"
        if (Test-Path $dataPrevious) { "FAIL:发现残留数据目录 $dataPrevious，请确认后手动处理"; return }
        try {
            if (Test-Path $DATA) { Move-Item -LiteralPath $DATA -Destination $dataPrevious -ErrorAction Stop }
            New-Item -ItemType Directory -Force -Path $DATA -ErrorAction Stop | Out-Null
        } catch {
            if ((Test-Path $dataPrevious) -and -not (Test-Path $DATA)) { Move-Item -LiteralPath $dataPrevious -Destination $DATA -ErrorAction SilentlyContinue }
            "FAIL:无法初始化账号$target 数据目录: $($_.Exception.Message)"; return
        }
        Remove-Item $dataPrevious -Recurse -Force -ErrorAction SilentlyContinue
        Log "账号$target 无存档，将以全新状态初始化"
    }
    $target | Out-File -Encoding ascii -NoNewline "$BASE\current.txt"
    # Only after the switch commits can the previous snapshot of the source be retired.
    if ($cur -in @('A','B')) { Remove-Item "$BASE\accounts\$cur.previous" -Recurse -Force -ErrorAction SilentlyContinue }
    Start-ClaudeApp
    Log "已切换到账号$target 并启动"
    "OK:已切换到账号$target"
}

switch ($args[0]) {
    'checkdetail' {
        $r = Invoke-CheckDetail
        $r | Out-File -Encoding utf8 "$BASE\last-check.txt"
        $r
    }
    'status' { Invoke-Status }
    'fix'    { Invoke-Fix }
    'switch' {
        $mutex = New-Object System.Threading.Mutex -ArgumentList $false, 'Local\ClaudeSwitcherAccountMutation'
        $acquired = $false
        try {
            try { $acquired = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
            if (-not $acquired) { "FAIL:另一个账号操作正在进行，请稍后重试"; exit 1 }
            Invoke-Switch $args[1]
        } catch { "FAIL:$($_.Exception.Message)"; exit 1 }
        finally { if ($acquired) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
    }
    'set-region' {
        try { Invoke-SetRegion -Confirmed:($args[1] -ceq '--confirm') }
        catch { "FAIL:$($_.Exception.Message)"; exit 1 }
    }
    default  { "用法: claude-switch.ps1 checkdetail|status|fix|set-region|switch A|B" }
}
