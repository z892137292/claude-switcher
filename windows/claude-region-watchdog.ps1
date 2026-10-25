$ErrorActionPreference = 'SilentlyContinue'
$BASE = Join-Path $env:USERPROFILE '.claude-switcher'
$REGION_FILE = Join-Path $BASE 'region.json'
$LOG = Join-Path $BASE 'region-watchdog.log'
. (Join-Path $PSScriptRoot 'region-functions.ps1')
New-Item -ItemType Directory -Force -Path $BASE | Out-Null

function Write-RegionLog([string]$message) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $message" | Out-File -Append -Encoding UTF8 $LOG
}

$current = if (Test-Path $REGION_FILE) { try { Get-Content $REGION_FILE -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop } catch { $null } } else { $null }
if (-not $current -or -not $current.exit_ip -or -not $current.country) {
    Write-RegionLog '缺少有效出口基准，请退出 Claude 后手动重新锁定；未自动创建基准'
    exit 1
}
# region-candidate.json is legacy state. It must never authorize a new baseline.
if ($current.tz_windows -and (Get-TimeZone).Id -ne $current.tz_windows) {
    try {
        Set-TimeZone -Id $current.tz_windows -ErrorAction Stop
        Write-RegionLog "时区漂移已恢复为 $($current.tz_windows)"
    } catch { Write-RegionLog "时区恢复失败：$($_.Exception.Message)" }
}
if ($current.culture -and (Get-Culture).Name -ne $current.culture) {
    try { Set-Culture -CultureInfo $current.culture -ErrorAction Stop; Write-RegionLog "地区格式漂移已恢复为 $($current.culture)" }
    catch { Write-RegionLog "地区格式恢复失败：$($_.Exception.Message)" }
}
