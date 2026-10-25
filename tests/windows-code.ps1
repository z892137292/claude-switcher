# Isolated Code launcher tests: fake CLI, fake processes, no real account or network.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sandbox=Join-Path ([System.IO.Path]::GetTempPath()) ('claude-code-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $sandbox | Out-Null
$oldProfile=$env:USERPROFILE;$oldAppData=$env:APPDATA;$oldConfig=$env:CLAUDE_CONFIG_DIR
$passed=0
function Assert([bool]$ok,[string]$message) { if(-not $ok){throw $message};$script:passed++ }
function Import-TestFunction([string]$file,[string]$name) {
    $t=$null;$e=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file),[ref]$t,[ref]$e)
    $fn=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    . ([scriptblock]::Create($fn.Extent.Text.Replace("function $name","function script:$name")))
}
try {
    $env:USERPROFILE=$sandbox;$env:APPDATA=Join-Path $sandbox 'AppData'
    $BASE=Join-Path $sandbox '.claude-switcher'
    New-Item -ItemType Directory $BASE | Out-Null
    . (Join-Path $root 'windows/code-functions.ps1')
    Assert ((Get-LaunchMode) -eq 'code') 'Fresh install must launch Code'
    Assert ((Get-CodeProfilePath A) -eq (Join-Path $sandbox '.claude')) 'A must preserve original Code config'
    Assert ((Get-CodeProfilePath B) -ne (Get-CodeProfilePath A)) 'A and B share a config path'
    $bad=$false;try{Get-CodeProfilePath '../A'}catch{$bad=$true}
    Assert $bad 'Invalid account path accepted'
    $project=Join-Path $sandbox "project 中文's folder"
    New-Item -ItemType Directory $project | Out-Null
    Set-CodeWorkspace $project
    Assert ((Get-LaunchSettings).workspace -eq $project) 'Project path did not round trip'
    $bad=$false;try{Set-CodeWorkspace (Join-Path $sandbox 'missing')}catch{$bad=$true}
    Assert ($bad -and (Get-LaunchSettings).workspace -eq $project) 'Missing project replaced valid config'
    $native=Join-Path $sandbox '.local/bin/claude.exe'
    New-Item -ItemType Directory (Split-Path $native -Parent) -Force | Out-Null
    'fake native' | Set-Content $native
    Assert ((Resolve-CodeCommand) -eq $native) 'Native Code not detected'
    Remove-Item $native
    $npm=Join-Path $env:APPDATA 'npm/claude.cmd'
    New-Item -ItemType Directory (Split-Path $npm -Parent) -Force | Out-Null
    'fake npm' | Set-Content $npm
    Assert ((Resolve-CodeCommand) -eq $npm) 'npm Code not detected'
    Remove-Item $npm
    function Get-Command { return $null }
    $bad=$false;try{Resolve-CodeCommand}catch{$bad=$true}
    Assert $bad 'Missing Code silently accepted'
    Remove-Item Function:Get-Command

    # Code route must never enter the Desktop snapshot path.
    Import-TestFunction 'windows/claude-switch.ps1' 'Invoke-Switch'
    function Invoke-CodeLaunch {param($account) "CODE:$account"}
    function Save-Account {throw 'Desktop snapshot touched'}
    $output=Invoke-Switch B
    Assert ($output -eq 'CODE:B' -and -not (Test-Path (Join-Path $BASE 'accounts'))) 'Code switch used Desktop data'
    Assert ((Invoke-Switch Z) -match 'FAIL:') 'Invalid account launch accepted'

    # A fake process tree proves unrelated node.exe and recycled PIDs are not stopped.
    $runs=Join-Path $BASE 'code-runs';New-Item -ItemType Directory $runs | Out-Null
    $stamp=[datetime]::UtcNow.AddMinutes(-1)
    @{pid=123;started_ticks=$stamp.Ticks;account='A';status='running'} | ConvertTo-Json | Set-Content (Join-Path $runs 'one.json')
    $processes=@{
        123=[pscustomobject]@{Id=123;ProcessName='powershell';StartTime=$stamp}
        124=[pscustomobject]@{Id=124;ProcessName='cmd';StartTime=$stamp.AddSeconds(1)}
        125=[pscustomobject]@{Id=125;ProcessName='node';StartTime=$stamp.AddSeconds(2)}
        900=[pscustomobject]@{Id=900;ProcessName='node';StartTime=$stamp.AddSeconds(3)}
    }
    function Get-Process {param([int]$Id) return $processes[$Id]}
    function Get-CimInstance {
        return @(
            [pscustomobject]@{ProcessId=123;ParentProcessId=1;CreationDate=$stamp},
            [pscustomobject]@{ProcessId=124;ParentProcessId=123;CreationDate=$stamp.AddSeconds(1)},
            [pscustomobject]@{ProcessId=125;ParentProcessId=124;CreationDate=$stamp.AddSeconds(2)},
            [pscustomobject]@{ProcessId=900;ParentProcessId=1;CreationDate=$stamp.AddSeconds(3)}
        )
    }
    $stopped=New-Object System.Collections.Generic.List[int]
    function Stop-Process {param([int]$Id,[switch]$Force) $stopped.Add($Id)}
    Assert (@(Get-ManagedCodeSessions).Count -eq 1) 'Managed session identity not recognized'
    Stop-ManagedCodeSessions
    Assert (($stopped -join ',') -eq '125,124,123') 'Process cleanup killed wrong processes or wrong order'
    $processes[123].StartTime=$stamp.AddMinutes(1)
    Assert (@(Get-ManagedCodeSessions).Count -eq 0) 'Recycled PID accepted as protected session'
    $stopped.Clear();Stop-ManagedCodeSessions
    Assert ($stopped.Count -eq 0) 'Recycled wrapper caused unrelated process termination'
    Remove-Item Function:Get-Process,Function:Get-CimInstance,Function:Stop-Process

    # Launch gate must reject drift before running any command.
    . (Join-Path $root 'windows/region-functions.ps1')
    Import-TestFunction 'windows/claude-switch.ps1' 'Invoke-CodePreflight'
    function Test-ProxyAlive {return $true};function Test-TunUp {return $true}
    function Get-ScheduledTask {return [pscustomobject]@{State='Running'}}
    function Get-Egress {return @{ip='203.0.113.9';loc='US'}}
    $REGION_FILE=Join-Path $BASE 'region.json'
    Save-RegionInfo ([pscustomobject]@{exit_ip='203.0.113.8';country='US'}) $REGION_FILE
    $bad=$false;try{Invoke-CodePreflight}catch{$bad=$true}
    Assert $bad 'Code preflight accepted changed exit'
    function Get-Egress {return @{ip='203.0.113.8';loc='US'}}
    Assert ((Invoke-CodePreflight) -eq 'OK:code-preflight') 'Matching Code preflight rejected'
    function Get-ScheduledTask {return [pscustomobject]@{State='Ready'}}
    $bad=$false;try{Invoke-CodePreflight}catch{$bad=$true}
    Assert $bad 'Code preflight accepted a stopped bodyguard'

    if ($env:OS -eq 'Windows_NT') {
        # Actual Windows PowerShell child, fake npm CLI and preflight. It cannot
        # contact Claude or read real credentials because USERPROFILE is isolated.
        Copy-Item (Join-Path $root 'windows/code-session.ps1') $BASE
        Copy-Item (Join-Path $root 'windows/code-functions.ps1') $BASE
        "'OK:code-preflight'" | Set-Content (Join-Path $BASE 'claude-switch.ps1') -Encoding UTF8
        @('@echo off','echo %CLAUDE_CONFIG_DIR%>"%USERPROFILE%\observed-profile.txt"','cd>"%USERPROFILE%\observed-workspace.txt"','exit /b 0') | Set-Content $npm -Encoding ascii
        $inputFile=Join-Path $sandbox 'input.txt';"`n" | Set-Content $inputFile
        $oldA=Get-CodeProfilePath A
        New-Item -ItemType Directory $oldA -Force | Out-Null
        'existing-login-sentinel' | Set-Content (Join-Path $oldA 'sentinel')
        foreach($account in @('A','B')) {
            $id=[guid]::NewGuid().ToString('N')
            $runner=Join-Path $BASE 'code-session.ps1'
            $argsLine='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Account {1} -RunId {2}' -f $runner,$account,$id
            $child=Start-Process powershell.exe -ArgumentList $argsLine -Wait -PassThru -RedirectStandardInput $inputFile -RedirectStandardOutput (Join-Path $sandbox 'out.txt') -RedirectStandardError (Join-Path $sandbox 'err.txt')
            $state=Get-Content (Join-Path $runs "$id.json") -Raw | ConvertFrom-Json
            Assert ($state.status -eq 'exited' -and $state.detail -eq 'exit=0') 'Fake CLI did not finish successfully'
            Assert ((Get-Content (Join-Path $sandbox 'observed-profile.txt')).Trim() -eq (Get-CodeProfilePath $account)) 'Child did not receive account config directory'
            Assert ((Get-Content (Join-Path $sandbox 'observed-workspace.txt')).Trim() -eq $project) 'Child started in wrong project directory'
            Assert ((Get-Content (Join-Path $oldA 'sentinel')).Trim() -eq 'existing-login-sentinel') 'Existing Code config modified'
        }
        # The caller gets UTF-8 text through a file even on a legacy code page.
        $stub=Join-Path $sandbox "stub 中文's.ps1"
        "'FAIL:未找到 Claude Code，请先安装'" | Set-Content $stub -Encoding UTF8
        $text=Invoke-CoreUtf8 $stub $BASE 'switch' 'A'
        Assert ($text.Trim() -eq 'FAIL:未找到 Claude Code，请先安装') 'Chinese error was corrupted by native stdout decoding'
        Assert (@(Get-ChildItem $BASE -Filter 'operation-*.txt').Count -eq 0) 'UTF-8 result temp file leaked'
    }
    Write-Host "PASS: $passed Claude Code assertions"
} finally {
    $env:USERPROFILE=$oldProfile;$env:APPDATA=$oldAppData;$env:CLAUDE_CONFIG_DIR=$oldConfig
    Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
