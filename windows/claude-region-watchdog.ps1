$ErrorActionPreference = 'SilentlyContinue'
$BASE = Join-Path $env:USERPROFILE '.claude-switcher'
$REGION_FILE = Join-Path $BASE 'region.json'
$PENDING_FILE = Join-Path $BASE 'region-candidate.json'
$LOG = Join-Path $BASE 'region-watchdog.log'
. (Join-Path $PSScriptRoot 'region-functions.ps1')
New-Item -ItemType Directory -Force -Path $BASE | Out-Null

function Write-RegionLog([string]$message) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $message" | Out-File -Append -Encoding UTF8 $LOG
}

$detected = Get-RegionInfo
if (-not $detected.country) { Write-RegionLog '出口国家探测失败，保留现有地区配置'; exit 0 }
if ($detected.country -eq 'CN' -and $env:FORCE -ne '1') { Write-RegionLog '出口国家为 CN，拒绝自动同步'; exit 0 }
$current = if (Test-Path $REGION_FILE) { try { Get-Content $REGION_FILE -Raw | ConvertFrom-Json } catch { $null } } else { $null }
if (-not $detected.tz_windows) {
    $detected.tz_windows = if ($current.tz_windows) { $current.tz_windows } else { (Get-TimeZone).Id }
    Write-RegionLog "无法映射 $($detected.tz_iana)，保持现有时区 $($detected.tz_windows)"
}

if (-not $current -or $current.country -ne $detected.country) {
    $pending = if (Test-Path $PENDING_FILE) { try { Get-Content $PENDING_FILE -Raw | ConvertFrom-Json } catch { $null } } else { $null }
    if ($pending -and $pending.country -eq $detected.country) {
        Save-RegionInfo $detected $REGION_FILE
        Remove-Item $PENDING_FILE -Force
        Apply-RegionUserSettings $detected | Out-Null
        $result = Apply-RegionSystemSettings $detected
        Write-RegionLog "连续两次探测到 $($detected.country)，已同步 $($detected.tz_windows)/$($detected.culture)：$($result -join '; ')"
        exit 0
    }
    $detected | Select-Object country,tz_windows,tz_iana,culture,updated_at | ConvertTo-Json |
        Set-Content -Path $PENDING_FILE -Encoding UTF8
    Write-RegionLog "发现出口国家变化为 $($detected.country)，等待下一次一致探测确认"
    exit 0
}

Remove-Item $PENDING_FILE -Force -ErrorAction SilentlyContinue
if ($detected.tz_windows -and $current.tz_windows -ne $detected.tz_windows) {
    Save-RegionInfo $detected $REGION_FILE
    Apply-RegionUserSettings $detected | Out-Null
    $result = Apply-RegionSystemSettings $detected
    Write-RegionLog "出口国家未变，时区 IANA 目标更新为 $($detected.tz_iana)：$($result -join '; ')"
} elseif ($current.tz_windows -and (Get-TimeZone).Id -ne $current.tz_windows) {
    try {
        Set-TimeZone -Id $current.tz_windows -ErrorAction Stop
        Write-RegionLog "时区漂移已恢复为 $($current.tz_windows)"
    } catch { Write-RegionLog "时区恢复失败：$($_.Exception.Message)" }
}
if ($current.culture -and (Get-Culture).Name -ne $current.culture) {
    try { Set-Culture -CultureInfo $current.culture -ErrorAction Stop; Write-RegionLog "地区格式漂移已恢复为 $($current.culture)" }
    catch { Write-RegionLog "地区格式恢复失败：$($_.Exception.Message)" }
}
