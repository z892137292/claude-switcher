# Claude Code launch profiles. No credentials are read or copied by this helper.
function Get-LaunchSettings {
    $path = Join-Path $BASE 'launch.json'
    if (Test-Path -LiteralPath $path) {
        try { return Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
        catch { throw '启动配置 launch.json 无法读取，请修复配置后重试' }
    }
    return [pscustomobject]@{ mode='code'; workspace=$env:USERPROFILE }
}

function Get-LaunchMode {
    $mode = (Get-LaunchSettings).mode
    if ($mode -notin @('code','desktop')) { throw '启动模式必须为 code 或 desktop' }
    return $mode
}

function Save-LaunchSettings($settings) {
    $path = Join-Path $BASE 'launch.json'
    $temp = "$path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $settings | ConvertTo-Json | Set-Content -LiteralPath $temp -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $temp -Destination $path -Force -ErrorAction Stop
    } finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

function Set-CodeWorkspace([string]$path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Container)) { throw '请选择存在的项目文件夹' }
    $fullPath = (Get-Item -LiteralPath $path -ErrorAction Stop).FullName
    $settings = Get-LaunchSettings
    $settings | Add-Member -NotePropertyName workspace -NotePropertyValue $fullPath -Force
    Save-LaunchSettings $settings
}

function Resolve-CodeCommand {
    # Native installation and npm installation; no Desktop application paths.
    $known = @((Join-Path $env:USERPROFILE '.local/bin/claude.exe'))
    if ($env:APPDATA) { $known += Join-Path $env:APPDATA 'npm/claude.cmd' }
    foreach ($path in $known) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { return (Get-Item -LiteralPath $path).FullName }
    }
    foreach ($name in @('claude.exe','claude.cmd','claude.ps1')) {
        $cmd = Get-Command $name -CommandType Application,ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd -and (Test-Path -LiteralPath $cmd.Source -PathType Leaf)) { return $cmd.Source }
    }
    throw '未找到 Claude Code。请先在 PowerShell 中确认 claude --version 可以运行，再重开切换器。无需安装 Claude 桌面版。'
}

function Get-CodeProfilePath([string]$account) {
    if ($account -eq 'A') { return [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.claude')) }
    if ($account -eq 'B') { return [System.IO.Path]::GetFullPath((Join-Path $BASE 'code-profiles/B')) }
    throw 'Code 配置必须为 A 或 B'
}

function Get-ManagedCodeSessions {
    $runs = Join-Path $BASE 'code-runs'
    if (-not (Test-Path -LiteralPath $runs)) { return }
    foreach ($file in Get-ChildItem -LiteralPath $runs -Filter '*.json' -File -ErrorAction Stop) {
        try {
            $r = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($r.status -notin @('starting','running') -or $r.pid -le 0) { continue }
            $process = Get-Process -Id ([int]$r.pid) -ErrorAction Stop
            if ($process.ProcessName -ne 'powershell' -or $process.StartTime.ToUniversalTime().Ticks -ne [long]$r.started_ticks) { continue }
            [pscustomobject]@{ pid=[int]$r.pid; started_ticks=[long]$r.started_ticks; account=$r.account; path=$file.FullName }
        } catch { continue }
    }
}

function Stop-ManagedCodeSessions {
    # Track wrapper identity, not every claude.exe/node.exe on the machine.
    foreach ($session in @(Get-ManagedCodeSessions)) {
        $snapshot = @(Get-CimInstance Win32_Process -ErrorAction Stop)
        $ids = New-Object System.Collections.Generic.List[int]
        $ids.Add([int]$session.pid)
        for ($index=0; $index -lt $ids.Count; $index++) {
            foreach ($child in $snapshot | Where-Object { $_.ParentProcessId -eq $ids[$index] }) {
                if (-not $ids.Contains([int]$child.ProcessId)) { $ids.Add([int]$child.ProcessId) }
            }
        }
        for ($index=$ids.Count-1; $index -ge 0; $index--) {
            $procId = $ids[$index]
            $process = Get-Process -Id $procId -ErrorAction SilentlyContinue
            if (-not $process) { continue }
            if ($procId -eq $session.pid) {
                if ($process.StartTime.ToUniversalTime().Ticks -ne $session.started_ticks) { continue }
            } else {
                $observed = $snapshot | Where-Object { $_.ProcessId -eq $procId } | Select-Object -First 1
                if (-not $observed.CreationDate -or [Math]::Abs(($process.StartTime.ToUniversalTime() - $observed.CreationDate.ToUniversalTime()).TotalMilliseconds) -gt 1) { continue }
            }
            Stop-Process -Id $procId -Force -ErrorAction Stop
        }
    }
}

function Write-CodeSessionState([string]$path, [string]$account, [string]$status, [string]$detail = '') {
    $self = Get-Process -Id $PID -ErrorAction Stop
    $json = [pscustomobject]@{
        pid=$PID; started_ticks=$self.StartTime.ToUniversalTime().Ticks; account=$account
        status=$status; detail=$detail
    } | ConvertTo-Json
    $temp = "$path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [System.IO.File]::WriteAllText($temp, $json, (New-Object System.Text.UTF8Encoding -ArgumentList $true))
        if ([System.IO.File]::Exists($path)) {
            $backup = "$temp.bak"
            [System.IO.File]::Replace($temp,$path,$backup)
            [System.IO.File]::Delete($backup)
        } else { [System.IO.File]::Move($temp,$path) }
    } finally { if ([System.IO.File]::Exists($temp)) { [System.IO.File]::Delete($temp) } }

}

function Invoke-CoreUtf8([string]$corePath, [string]$basePath, [string]$command, [string]$account = '') {
    # PS 5.1's native stdout decoding depends on the parent's code page. Exchange
    # operation results through an explicitly UTF-8 file instead of that pipe.
    $outputPath = Join-Path $basePath ('operation-' + [guid]::NewGuid().ToString('N') + '.txt')
    $argv = @($command)
    if ($account) { $argv += $account }
    if ($command -eq 'set-region') { $argv += '--confirm' }
    $quoted = @($argv | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ' '
    $coreLiteral = "'" + $corePath.Replace("'", "''") + "'"
    $outputLiteral = "'" + $outputPath.Replace("'", "''") + "'"
    $body = "try { & $coreLiteral $quoted 2>&1 | Out-File -LiteralPath $outputLiteral -Encoding utf8 } catch { ('FAIL:' + `$_.Exception.Message) | Out-File -LiteralPath $outputLiteral -Encoding utf8 }"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
    try {
        $null = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded 2>&1
        if (-not (Test-Path -LiteralPath $outputPath)) { return 'FAIL:核心脚本未返回结果，请重新安装完整版本' }
        return Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 -ErrorAction Stop
    } finally { Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue }
}
