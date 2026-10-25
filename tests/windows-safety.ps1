# Isolated regression tests. No real proxy, account, scheduled task or system changes.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$testDir = Join-Path ([System.IO.Path]::GetTempPath()) ('claude-safety-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $testDir | Out-Null
$originalProfile = $env:USERPROFILE
$script:passed = 0
function Assert([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
    $script:passed++
}
function Import-TestFunction([string]$file, [string]$name) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file), [ref]$tokens, [ref]$errors)
    $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if (-not $definition) { throw "Missing function: $name" }
    # Set in script scope, without executing the file's installer/daemon entry point.
    . ([scriptblock]::Create($definition.Extent.Text.Replace("function $name", "function script:$name")))
}
try {
    foreach ($file in Get-ChildItem (Join-Path $root 'windows') -Filter '*.ps1') {
        $tokens=$null; $errors=$null
        [System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors) | Out-Null
        Assert ($errors.Count -eq 0) "$($file.Name): $errors"
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        Assert ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) "Missing UTF-8 BOM: $file"
    }
    . (Join-Path $root 'windows/region-functions.ps1')
    . (Join-Path $root 'windows/code-functions.ps1')
    function Get-LaunchMode { return 'desktop' }
    function curl.exe {
        $global:LASTEXITCODE = 0
        if ($script:mode -eq 'offline') { $global:LASTEXITCODE=28; return }
        if ($args -contains 'https://ipinfo.io/json') {
            switch ($script:mode) {
                'fallback' { $global:LASTEXITCODE=22; return }
                'partial' { return '{"country":"JP","timezone":"Asia/Tokyo"}' }
                'unknown' { return '{"country":"ZZ","timezone":"Etc/Unknown","ip":"203.0.113.8"}' }
                default { return '{"country":"JP","timezone":"Asia/Tokyo","ip":"203.0.113.8","org":"Example"}' }
            }
        }
        if ($args -contains 'https://ipinfo.io/timezone') { $global:LASTEXITCODE=22; return }
        return "ip=203.0.113.9`nloc=GB"
    }
    $script:mode='ipinfo'; $region=Get-RegionInfo
    Assert ($region.country -eq 'JP' -and $region.tz_windows -eq 'Tokyo Standard Time' -and $region.culture -eq 'ja-JP') 'Region mapping failed'
    $path=Join-Path $testDir 'region.json'
    Save-RegionInfo $region $path
    $locked=Get-Content $path -Raw | ConvertFrom-Json
    Assert ($locked.exit_ip -eq '203.0.113.8' -and $locked.locked_at -and $locked.asn -eq 'Example') 'Baseline fields missing'
    $before=Get-Content $path -Raw
    Save-RegionInfo $locked $path
    Assert (([datetime](Get-Content $path -Raw | ConvertFrom-Json).locked_at) -eq ([datetime]$locked.locked_at)) 'Atomic replacement changed lock timestamp'
    $before=Get-Content $path -Raw
    $invalid=[pscustomobject]@{exit_ip='broken';country='JP'}
    $threw=$false; try { Save-RegionInfo $invalid $path } catch { $threw=$true }
    Assert ($threw -and (Get-Content $path -Raw) -eq $before) 'Invalid update overwrote baseline'
    Assert (@(Get-ChildItem $testDir -Filter '*.tmp').Count -eq 0) 'Temporary baseline file leaked'
    Assert ((Test-RegionEgressMatch '203.0.113.8' 'jp' $locked).passed) 'Matching exit rejected'
    Assert (-not (Test-RegionEgressMatch '203.0.113.9' 'JP' $locked).passed) 'IP drift accepted'
    Assert (-not (Test-RegionEgressMatch '203.0.113.8' 'GB' $locked).passed) 'Country drift accepted'
    Assert (-not (Test-RegionEgressMatch '' '' $locked).passed) 'Unknown exit accepted'
    Assert (-not (Test-RegionEgressMatch '203.0.113.8' 'JP' $null).passed) 'Missing baseline accepted'
    Assert (-not (Test-RegionEgressMatch 'broken' 'JP' $invalid).passed) 'Invalid IP accepted'
    $v6=[pscustomobject]@{exit_ip='2001:db8::1';country='JP'}
    Assert ((Test-RegionEgressMatch '2001:0db8:0:0:0:0:0:1' 'JP' $v6).passed) 'Equivalent IPv6 rejected'
    Assert ((Test-RegionEgressMatch '203.0.113.9' 'JP' $locked).reason -notmatch '203\.0\.113\.[89]') 'Mismatch log contains full IP'
    foreach ($script:mode in @('fallback','partial')) {
        $r=Get-RegionInfo
        Assert ($r.country -eq 'GB' -and $r.ip -eq '203.0.113.9' -and $r.tz_iana -eq 'Europe/London') 'Fallback mixed observations from different exits'
    }
    $script:mode='unknown'; $r=Get-RegionInfo
    Assert (-not $r.tz_windows -and $r.culture -eq 'en-US') 'Unknown timezone silently mapped'
    $script:mode='offline'; $r=Get-Egress
    Assert (-not $r.ip -and -not $r.loc) 'Failed probe accepted'

    Import-TestFunction 'windows/claude-switch.ps1' 'Test-RulesPinned'
    $CLASH_DIR=Join-Path $testDir 'clash'
    New-Item -ItemType Directory (Join-Path $CLASH_DIR 'profiles') -Force | Out-Null
    $PROXY_GROUP='Proxy (US)'
    $rules=@('- DOMAIN-SUFFIX,claude.ai,Proxy (US)','- DOMAIN-SUFFIX,anthropic.com,Proxy (US)','- DST-PORT,3478,Proxy (US)','- DST-PORT,5349,Proxy (US)','- DST-PORT,19302,Proxy (US)')
    $merge=Join-Path $CLASH_DIR 'profiles/Merge.yaml'
    $rules | Set-Content $merge
    Assert (Test-RulesPinned) 'Complete pinned rules rejected'
    ($rules | ForEach-Object { "# $_" }) | Set-Content $merge
    Assert (-not (Test-RulesPinned)) 'Commented rules counted as active'
    ($rules -replace 'DST-PORT,3478,Proxy \(US\)', 'DST-PORT,3478,DIRECT') | Set-Content $merge
    Assert (-not (Test-RulesPinned)) 'DIRECT STUN rule accepted'
    ($rules -replace ',Proxy \(US\)$', ',Proxy (US) extra') | Set-Content $merge
    Assert (-not (Test-RulesPinned)) 'Proxy group prefix accepted'
    $rules[0,2,3,4] | Set-Content $merge
    Assert (-not (Test-RulesPinned)) 'Missing API domain accepted'
    $rules | Set-Content (Join-Path $CLASH_DIR 'clash-verge.yaml')
    Assert (Test-RulesPinned) 'Runtime rule file not recognized'
    $PROXY_GROUP='DIRECT'
    Assert (-not (Test-RulesPinned)) 'DIRECT selected as protected proxy group'

    $names=@('代理内核','TUN网卡','出口IP','IP一致','时区','地区','IPv6','DNS','WebRTC','保镖','规则置顶','客户端语言','ASN属性','生态可达性')
    $report=@($names | ForEach-Object { "$_=ok" })
    Assert ((Test-CheckReport $report).passed) 'Complete report rejected'
    Assert (-not (Test-CheckReport @()).passed) 'Empty report passed'
    Assert (-not (Test-CheckReport $report[0..12]).passed) 'Incomplete report passed'
    Assert (-not (Test-CheckReport ($report + $report[0])).passed) 'Duplicate report passed'
    $report[0]='代理内核=unknown'
    Assert (-not (Test-CheckReport $report).passed) 'Unknown state passed'
    $report[0]='代理内核=ok';$report[12]='ASN属性=info:Example'
    Assert ((Test-CheckReport $report).passed) 'Informational ASN blocked startup'

    # Bodyguard decisions with healthy virtual adapter but wrong/unknown exit.
    Import-TestFunction 'windows/claude-bodyguard.ps1' 'Get-GuardFailure'
    $BASE=$testDir
    Save-RegionInfo $locked $path
    function Get-TunStatus { return @{up=$script:tunUp} }
    function Test-ClientAlive { return $script:clientUp }
    function Get-Egress { return @{ip=$script:exitIp;loc=$script:exitCountry} }
    $script:tunUp=$true;$script:clientUp=$true;$script:exitIp='203.0.113.8';$script:exitCountry='JP'
    Assert (-not (Get-GuardFailure)) 'Healthy exit rejected by guard'
    $script:exitIp='203.0.113.9'
    Assert ([bool](Get-GuardFailure)) 'Guard accepted changed exit with healthy TUN'
    $script:exitIp=''
    Assert ([bool](Get-GuardFailure)) 'Guard accepted probe failure'
    $script:exitIp='203.0.113.8';$script:clientUp=$false
    Assert ([bool](Get-GuardFailure)) 'Guard accepted dead client'
    $script:clientUp=$true;$script:tunUp=$false
    Assert ([bool](Get-GuardFailure)) 'Guard accepted absent TUN'
    $script:tunUp=$true
    '{' | Set-Content $path
    Assert ([bool](Get-GuardFailure)) 'Guard accepted corrupt baseline'
    Save-RegionInfo $locked $path

    # The actual watchdog restores the saved settings, makes no network probe and preserves bytes.
    $env:USERPROFILE=$testDir
    $watchBase=Join-Path $testDir '.claude-switcher'
    New-Item -ItemType Directory $watchBase | Out-Null
    $watchPath=Join-Path $watchBase 'region.json'
    Save-RegionInfo $locked $watchPath
    $watchBefore=Get-Content $watchPath -Raw
    function Get-TimeZone { return [pscustomobject]@{Id='Wrong zone'} }
    function Get-Culture { return [pscustomobject]@{Name='wrong'} }
    $effects=@{}
    function Set-TimeZone { param($Id) $effects.zone=$Id }
    function Set-Culture { param($CultureInfo) $effects.culture=$CultureInfo }
    function curl.exe { throw 'Watchdog must never probe or relock exit' }
    & (Join-Path $root 'windows/claude-region-watchdog.ps1')
    Assert ((Get-Content $watchPath -Raw) -eq $watchBefore) 'Watchdog rewrote baseline'
    Assert ($effects.zone -eq $locked.tz_windows -and $effects.culture -eq $locked.culture) 'Watchdog did not restore saved settings'

    # Re-locking and account operations must reject bad state before touching real processes.
    Import-TestFunction 'windows/claude-switch.ps1' 'Invoke-SetRegion'
    function Get-RegionInfo { return [pscustomobject]@{ip='203.0.113.8';country='JP';tz_windows='Tokyo Standard Time'} }
    function Get-Process { return [pscustomobject]@{Name='Claude'} }
    $output=Invoke-SetRegion -Confirmed
    Assert ($output -match 'FAIL:') 'Relock allowed while Claude was running'
    Import-TestFunction 'windows/claude-switch.ps1' 'Invoke-Switch'
    function Invoke-CheckDetail { return '代理内核=ok' }
    $DATA=Join-Path $testDir 'Claude'
    $output=Invoke-Switch A
    Assert ($output -match 'FAIL:' -and -not (Test-Path $DATA)) 'Incomplete check report mutated account data'

    Import-TestFunction 'windows/claude-switch.ps1' 'Start-ClaudeApp'
    $REGION_FILE=$path
    $script:exitIp='203.0.113.9';$script:exitCountry='JP'
    $threw=$false; try { Start-ClaudeApp } catch { $threw=$true }
    Assert $threw 'Final launch did not block changed egress'
    $script:exitIp='203.0.113.8'
    function Test-ProxyAlive { return $false }
    function Test-TunUp { return $true }
    $threw=$false; try { Start-ClaudeApp } catch { $threw=$true }
    Assert $threw 'Final launch did not block dead proxy'

    # Archive source .previous must be retired after successful A->B, enabling B->A->B.
    foreach ($fn in @('Save-Account','Stop-ClaudeApp')) { Import-TestFunction 'windows/claude-switch.ps1' $fn }
    function Get-Process { return $null }
    function Start-ClaudeApp { }
    function Log { param($message) }
    function robocopy {
        param($source,$dest)
        New-Item -ItemType Directory $dest -Force | Out-Null
        Get-ChildItem $source | Copy-Item -Destination $dest -Recurse -Force
        $global:LASTEXITCODE=1
    }
    function Invoke-CheckDetail { return @($names | ForEach-Object { "$_=ok" }) }
    New-Item -ItemType Directory (Join-Path $BASE 'accounts') -Force | Out-Null
    New-Item -ItemType Directory $DATA | Out-Null
    'A session' | Set-Content (Join-Path $DATA 'session')
    $null=Invoke-Switch B
    'B session' | Set-Content (Join-Path $DATA 'session')
    foreach ($account in @('A','B','A','B')) {
        $output=Invoke-Switch $account
        Assert ($output -match 'OK:' -and $output -notmatch 'FAIL:') "Repeated switch failed: $output"
        Assert ((Get-Content (Join-Path $DATA 'session')).Trim() -eq "$account session") 'Wrong account session restored'
    }
    $global:LASTEXITCODE=0
    function robocopy { $global:LASTEXITCODE=8 }
    $beforeSession=Get-Content (Join-Path $DATA 'session') -Raw
    $output=Invoke-Switch A
    Assert ($output -match 'FAIL:' -and (Get-Content (Join-Path $DATA 'session') -Raw) -eq $beforeSession) 'Failed archive destroyed active data'
    # Residual Fake-IP addresses must not make a stopped or unrelated adapter pass.
    foreach ($source in @('windows/claude-switch.ps1','windows/claude-bodyguard.ps1')) {
        Import-TestFunction $source 'Get-TunStatus'
        function Get-NetIPAddress { return [pscustomobject]@{IPAddress='198.18.0.1';InterfaceIndex=25;AddressState='Preferred'} }
        function Get-NetAdapter { return [pscustomobject]@{ifIndex=25;Name='Mihomo';Status='Disconnected';InterfaceDescription='Meta Tunnel'} }
        Assert (-not (Get-TunStatus).up) 'Residual address on disconnected adapter passed'
        function Get-NetAdapter { return [pscustomobject]@{ifIndex=26;Name='Other';Status='Up';InterfaceDescription='Meta Tunnel'} }
        Assert (-not (Get-TunStatus).up) 'Address belonging to another adapter passed'
        function Get-NetAdapter { return [pscustomobject]@{ifIndex=25;Name='Mihomo';Status='Up';InterfaceDescription='Meta Tunnel'} }
        Assert ((Get-TunStatus).up) 'Active tunnel with preferred address rejected'
        function Get-NetIPAddress { return [pscustomobject]@{IPAddress='198.18.0.1';InterfaceIndex=25;AddressState='Tentative'} }
        Assert (-not (Get-TunStatus).up) 'Tentative tunnel address passed'
    }
    Write-Host "PASS: $script:passed Windows safety assertions"
} finally {
    $env:USERPROFILE=$originalProfile
    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
}
