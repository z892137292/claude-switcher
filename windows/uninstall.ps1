# Claude 切换器卸载器 (Windows) —— 需管理员运行
# 移除保镖计划任务、桌面快捷方式与程序文件;保留 accounts 账号存档,避免误删登录态
$ErrorActionPreference = 'Continue'
$BASE = Join-Path $env:USERPROFILE ".claude-switcher"

Stop-ScheduledTask -TaskName 'ClaudeBodyguard' -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'ClaudeBodyguard' -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "[OK] 保镖计划任务已移除" -ForegroundColor Green

Remove-Item "$env:USERPROFILE\Desktop\Claude切换器.lnk" -ErrorAction SilentlyContinue
Write-Host "[OK] 桌面快捷方式已移除" -ForegroundColor Green

foreach ($f in 'claude-switch.ps1','SwitcherUI.ps1','claude-bodyguard.ps1','proxy-mode.txt','lastip.txt','last-check.txt','bodyguard.log','uninstall.ps1') {
    Remove-Item (Join-Path $BASE $f) -ErrorAction SilentlyContinue
}
Write-Host "[OK] 程序文件已移除(账号存档 $BASE\accounts 已保留,确认无用后可手动删除)" -ForegroundColor Green
pause
