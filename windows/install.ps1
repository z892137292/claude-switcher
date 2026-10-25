# Claude 切换器 Windows 版 - 安装器
# 右键 -> 使用 PowerShell 以管理员身份运行(或在管理员 PowerShell 里执行)
$ErrorActionPreference = 'Stop'
$BASE = "$env:USERPROFILE\.claude-switcher"
. "$PSScriptRoot\region-functions.ps1"
$CLASH_DIR = @(
    "$env:APPDATA\io.github.clash-verge-rev.clash-verge-rev",
    "$env:LOCALAPPDATA\io.github.clash-verge-rev.clash-verge-rev"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "  Claude 账号切换器 · Windows 安装" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# ---- 0. 前置检查 + 代理客户端探测 ----
$PROXY_MODE = $null
if ($CLASH_DIR) {
    $PROXY_MODE = 'clash-verge'
} elseif (Get-Process -Name 'sing-box' -ErrorAction SilentlyContinue) {
    $PROXY_MODE = 'sing-box'
} elseif (Get-Process -Name 'ClashX' -ErrorAction SilentlyContinue) {
    $PROXY_MODE = 'clashx'
} elseif (Get-Process -Name 'Surge' -ErrorAction SilentlyContinue) {
    $PROXY_MODE = 'surge'
} elseif (Get-Service -Name 'WireGuardTunnel*' -ErrorAction SilentlyContinue | Where-Object Status -eq 'Running') {
    $PROXY_MODE = 'wireguard'
}
if (-not $PROXY_MODE) {
    Write-Host "未自动识别到代理客户端,请选择:" -ForegroundColor Yellow
    Write-Host "  1) clash-verge  2) sing-box  3) clashx  4) surge"
    Write-Host "  5) wireguard    6) other(仅TUN)  7) auto(任一命中即活)"
    $pick = Read-Host "请输入序号或名称(直接回车=auto)"
    switch ($pick) {
        '1' { $PROXY_MODE = 'clash-verge' }
        '2' { $PROXY_MODE = 'sing-box' }
        '3' { $PROXY_MODE = 'clashx' }
        '4' { $PROXY_MODE = 'surge' }
        '5' { $PROXY_MODE = 'wireguard' }
        '6' { $PROXY_MODE = 'other' }
        '7' { $PROXY_MODE = 'auto' }
        'clash-verge' { $PROXY_MODE = 'clash-verge' }
        'sing-box'    { $PROXY_MODE = 'sing-box' }
        'clashx'      { $PROXY_MODE = 'clashx' }
        'surge'       { $PROXY_MODE = 'surge' }
        'wireguard'   { $PROXY_MODE = 'wireguard' }
        'other'       { $PROXY_MODE = 'other' }
        'auto'        { $PROXY_MODE = 'auto' }
        default       { $PROXY_MODE = 'auto' }
    }
}
Write-Host "[OK] 代理客户端: $PROXY_MODE" -ForegroundColor Green
Write-Host "[OK] 前置检查通过" -ForegroundColor Green

# ---- 1. 按出口IP识别地区 ----
$region = Get-RegionInfo
$country = $region.country
$ip = $region.ip
$FORCE = $env:FORCE
if ($country -eq 'CN' -and $FORCE -ne '1') {
    Write-Host "X 当前出口在国内(CN),请先开启代理(TUN模式)并确认节点可用再运行" -ForegroundColor Red
    pause; exit 1
}
if (-not $country) {
    Write-Host "X 未能识别出口国家,请确认代理已开启后重试" -ForegroundColor Red
    pause; exit 1
}
Write-Host "[OK] 出口: $ip ($country)" -ForegroundColor Green
if (-not $region.tz_windows) {
    $region.tz_windows = (Get-TimeZone).Id
    Write-Host "[WARN] 未识别到时区映射($($region.tz_iana)),保留当前时区 $($region.tz_windows)" -ForegroundColor Yellow
}
Save-RegionInfo $region "$BASE\region.json"
Write-Host "[OK] 地区目标: $($region.country) / $($region.tz_iana) / $($region.culture)" -ForegroundColor Green

# ---- 2. 自动识别代理组名(仅 Clash Verge) ----
$grp = 'GLOBAL'
if ($PROXY_MODE -eq 'clash-verge' -and $CLASH_DIR) {
    $grp = $null
    $inGroups = $false; $name = $null
    foreach ($line in Get-Content "$CLASH_DIR\clash-verge.yaml" -ErrorAction SilentlyContinue) {
        if ($line -match '^proxy-groups:') { $inGroups = $true; continue }
        if ($inGroups -and $line -match '^[a-zA-Z]') { $inGroups = $false }
        if ($inGroups -and $line -match '- name:\s*(.+)') { $name = $Matches[1].Trim('"',"'",' ') }
        if ($inGroups -and $line -match 'type:\s*select') { $grp = $name; break }
    }
    if (-not $grp) { $grp = Read-Host "未能自动识别代理组名,请打开 Clash Verge 查看后输入" }
    if (-not $grp) { $grp = 'GLOBAL' }
    Write-Host "[OK] 代理组: $grp" -ForegroundColor Green
}

# ---- 4. 安装文件 ----
New-Item -ItemType Directory -Force -Path $BASE | Out-Null
Copy-Item "$PSScriptRoot\claude-switch.ps1"   "$BASE\claude-switch.ps1" -Force
Copy-Item "$PSScriptRoot\SwitcherUI.ps1"      "$BASE\SwitcherUI.ps1" -Force
Copy-Item "$PSScriptRoot\claude-bodyguard.ps1" "$BASE\claude-bodyguard.ps1" -Force
Copy-Item "$PSScriptRoot\claude-region-watchdog.ps1" "$BASE\claude-region-watchdog.ps1" -Force
Copy-Item "$PSScriptRoot\region-functions.ps1" "$BASE\region-functions.ps1" -Force

# 仅写入代理模式和代理组；国家/时区/地区格式保存在 region.json
$core = Get-Content "$BASE\claude-switch.ps1" -Raw
$modeEsc = $PROXY_MODE.Replace('$', '$$')
$grpEsc = $grp.Replace('$', '$$')
$core = $core -replace '\$PROXY_MODE = "[^"]*"', ('$$PROXY_MODE = "' + $modeEsc + '"')
$core = $core -replace '\$PROXY_GROUP = "[^"]*"', ('$$PROXY_GROUP = "' + $grpEsc + '"')
# 强制写回 UTF-8 BOM:计划任务用 powershell.exe 5.1 读取,无 BOM 会把中文读成乱码
$utf8Bom = New-Object System.Text.UTF8Encoding -ArgumentList $true
[System.IO.File]::WriteAllText("$BASE\claude-switch.ps1", $core, $utf8Bom)
$PROXY_MODE | Out-File -Encoding ascii -NoNewline "$BASE\proxy-mode.txt"
Write-Host "[OK] 核心文件已安装到 $BASE (代理模式: $PROXY_MODE)" -ForegroundColor Green

# ---- 5. 桌面快捷方式 ----
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut("$env:USERPROFILE\Desktop\Claude切换器.lnk")
$sc.TargetPath = "powershell.exe"
$sc.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$BASE\SwitcherUI.ps1`""
$sc.WorkingDirectory = $BASE
$sc.Save()
Write-Host "[OK] 桌面快捷方式已创建" -ForegroundColor Green

# ---- 6. 置顶规则(仅 Clash Verge) ----
if ($PROXY_MODE -eq 'clash-verge' -and $CLASH_DIR) {
    New-Item -ItemType Directory -Force -Path "$CLASH_DIR\profiles" | Out-Null
    @"
profile:
  store-selected: true

prepend-rules:
  - DOMAIN-SUFFIX,claude.ai,$grp
  - DOMAIN-SUFFIX,claude.com,$grp
  - DOMAIN-SUFFIX,anthropic.com,$grp
  - DOMAIN-SUFFIX,claudeusercontent.com,$grp
  - DOMAIN-SUFFIX,challenges.cloudflare.com,$grp
  - DOMAIN-SUFFIX,datadoghq.com,$grp
  - DOMAIN-SUFFIX,segment.io,$grp
  - DOMAIN-SUFFIX,stripe.com,$grp
  - DOMAIN-SUFFIX,stripe.network,$grp
  - DOMAIN-SUFFIX,stripecdn.com,$grp
  - DOMAIN-SUFFIX,intercom.io,$grp
  - DOMAIN-SUFFIX,intercomcdn.com,$grp
  - DOMAIN-SUFFIX,intercomassets.com,$grp
  - DST-PORT,3478,$grp
  - DST-PORT,5349,$grp
  - DST-PORT,19302,$grp
"@ | Out-File -Encoding utf8 "$CLASH_DIR\profiles\Merge.yaml"
    Write-Host "[OK] Claude 域名置顶规则已写入(重启 Clash Verge 后生效)" -ForegroundColor Green
} elseif ($PROXY_MODE -eq 'clash-verge') {
    Write-Host "[WARN] 未找到 Clash Verge 配置目录,跳过置顶规则;请手动在 Clash Verge 中添加" -ForegroundColor Yellow
} else {
    Write-Host "[OK] 非 Clash Verge:请在你的代理客户端中为 Claude 域名添加置顶/直连规则" -ForegroundColor Yellow
}

# ---- 7. 系统级配置 ----
Apply-RegionUserSettings $region | Out-Null
$regionResults = Apply-RegionSystemSettings $region
Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue | Where-Object { $_.Enabled } | Disable-NetAdapterBinding -Confirm:$false
Clear-DnsClientCache
Write-Host "[OK] 地区设置: $($regionResults -join '; ') / IPv6 已关闭 / DNS 缓存已刷新" -ForegroundColor Green

# ---- 8. 注册保镖计划任务 ----
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$BASE\claude-bodyguard.ps1`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName 'ClaudeBodyguard' -Action $action -Trigger $trigger -Force | Out-Null
Stop-ScheduledTask -TaskName 'ClaudeBodyguard' -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName 'ClaudeBodyguard'
Write-Host "[OK] 保镖已注册并启动(计划任务,登录自动运行)" -ForegroundColor Green

# ---- 8.1 地区看门狗(登录 + 每5分钟,最高权限) ----
$regionAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$BASE\claude-region-watchdog.ps1`""
$loginTrigger = New-ScheduledTaskTrigger -AtLogOn
$timerTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration ([TimeSpan]::FromDays(3650))
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName 'ClaudeRegionWatchdog' -Action $regionAction -Trigger @($loginTrigger,$timerTrigger) -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName 'ClaudeRegionWatchdog'
Write-Host "[OK] 地区看门狗已注册(登录启动 + 每5分钟,最高权限)" -ForegroundColor Green

# ---- 9. 重启 Clash 使规则生效(仅 Clash Verge) ----
if ($PROXY_MODE -eq 'clash-verge') {
    Get-Process -Name 'clash-verge','Clash Verge' -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep 2
    $cv = Get-ChildItem "$env:LOCALAPPDATA\Programs" -Recurse -Filter 'Clash Verge*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cv) { Start-Process $cv.FullName }
}

Write-Host ""
Write-Host "==================================" -ForegroundColor Green
Write-Host "  安装完成! 双击桌面「Claude切换器」使用" -ForegroundColor Green
Write-Host "  首次使用: 打开后选账号A(自动收编当前登录)" -ForegroundColor Green
Write-Host "==================================" -ForegroundColor Green
$checkOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$BASE\claude-switch.ps1" checkdetail 2>&1
Write-Host "`n安装后安全检查：" -ForegroundColor Cyan
$checkOutput | ForEach-Object {
    $color = if ($_ -match '=ok:') { 'Green' } elseif ($_ -match '=warn:') { 'Yellow' } elseif ($_ -match '=fail:') { 'Red' } else { 'Gray' }
    Write-Host $_ -ForegroundColor $color
}
pause
