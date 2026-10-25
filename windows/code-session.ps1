# Interactive terminal wrapper. Used only for sessions opened by this switcher.
param(
    [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$Account,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{32}$')][string]$RunId
)
$ErrorActionPreference = 'Stop'
$BASE = Join-Path $env:USERPROFILE '.claude-switcher'
. (Join-Path $PSScriptRoot 'code-functions.ps1')
$runFile = Join-Path (Join-Path $BASE 'code-runs') "$RunId.json"
try {
    Write-CodeSessionState $runFile $Account 'starting'
    # Do not trust the UI's earlier result: verify immediately before executing Code.
    $gate = @(& (Join-Path $PSScriptRoot 'claude-switch.ps1') code-preflight)
    if ($gate -notcontains 'OK:code-preflight') { throw '启动前安全核验未通过，请回到切换器重新检查' }
    $command = Resolve-CodeCommand
    $configPath = Get-CodeProfilePath $Account
    New-Item -ItemType Directory -Path $configPath -Force | Out-Null
    $settings = Get-LaunchSettings
    if (-not (Test-Path -LiteralPath $settings.workspace -PathType Container)) { throw '项目目录不存在，请重新选择项目' }
    Set-Location -LiteralPath $settings.workspace
    $env:CLAUDE_CONFIG_DIR = $configPath
    try { $host.UI.RawUI.WindowTitle = "Claude Code - $Account" } catch {}
    Write-Host "Claude Code 配置 $Account | 项目: $($settings.workspace)"
    Write-Host '首次使用该配置时，请按 Claude Code 提示登录。'
    $overrideNames = @('ANTHROPIC_API_KEY','ANTHROPIC_AUTH_TOKEN','CLAUDE_CODE_OAUTH_TOKEN','CLAUDE_CODE_USE_BEDROCK','CLAUDE_CODE_USE_VERTEX','CLAUDE_CODE_USE_FOUNDRY') | Where-Object { [Environment]::GetEnvironmentVariable($_) }
    if ($overrideNames) { Write-Warning "检测到继承的认证/供应商变量($($overrideNames -join ', '))，可能优先于该配置的登录；本工具未更改这些变量。" }
    Write-CodeSessionState $runFile $Account 'running'
    & $command
    $codeExit = $LASTEXITCODE
    Write-CodeSessionState $runFile $Account 'exited' "exit=$codeExit"
    Write-Host "Claude Code 已退出，退出码: $codeExit"
} catch {
    Write-CodeSessionState $runFile $Account 'failed' '启动失败，请查看终端提示'
    Write-Host "FAIL:$($_.Exception.Message)" -ForegroundColor Red
}
# This terminal is dedicated to one managed Code session; do not keep it as a general shell.

Read-Host '按回车关闭此终端' | Out-Null
