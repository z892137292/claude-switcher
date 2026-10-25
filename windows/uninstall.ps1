# Claude 切换器 Windows 卸载器
$ErrorActionPreference = 'Continue'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    } catch {
        Write-Host '需要管理员授权才能删除计划任务。'
        Read-Host '按回车退出'
    }
    exit
}
$BASE = Join-Path $env:USERPROFILE '.claude-switcher'

foreach ($task in @('ClaudeBodyguard','ClaudeRegionWatchdog')) {
    Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
}
$shortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Claude切换器.lnk'
Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue

Write-Host '已删除 ClaudeBodyguard / ClaudeRegionWatchdog 计划任务和桌面快捷方式。'
if (Test-Path $BASE) {
    $remove = Read-Host "是否删除 $BASE 下的配置和日志？(y/N)"
    if ($remove -match '^(y|yes)$') {
        $deleteAccounts = Read-Host '是否同时删除 accounts 账号存档？(y/N，默认保留)'
        if ($deleteAccounts -match '^(y|yes)$') {
            Remove-Item -LiteralPath $BASE -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            $accounts = Join-Path $BASE 'accounts'
            $keep = Join-Path $env:TEMP ("claude-switcher-accounts-" + [guid]::NewGuid().ToString('N'))
            if (Test-Path $accounts) { Move-Item -LiteralPath $accounts -Destination $keep -Force }
            Remove-Item -LiteralPath $BASE -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Force -Path $BASE | Out-Null
            if (Test-Path $keep) { Move-Item -LiteralPath $keep -Destination (Join-Path $BASE 'accounts') }
            Write-Host '配置和日志已删除，accounts 账号存档已保留。'
        }
    } else {
        Write-Host '已保留配置和账号存档。'
    }
}

Write-Host ''
Write-Host '如需恢复 IPv6，请在管理员 PowerShell 中运行：'
Write-Host 'Get-NetAdapterBinding -ComponentID ms_tcpip6 | Where-Object { -not $_.Enabled } | Enable-NetAdapterBinding -Confirm:$false'
Read-Host '按回车退出'
