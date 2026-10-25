$script:RegionCultureMap = @{
    US='en-US'; GB='en-GB'; JP='ja-JP'; KR='ko-KR'; TW='zh-TW'; HK='zh-HK'; SG='en-SG'; CN='zh-CN'
    DE='de-DE'; FR='fr-FR'; CA='en-CA'; AU='en-AU'; NZ='en-NZ'; IE='en-IE'; NL='nl-NL'
    CH='de-CH'; AT='de-AT'; BE='nl-BE'; ES='es-ES'; IT='it-IT'; PT='pt-PT'; SE='sv-SE'
    NO='nb-NO'; DK='da-DK'; FI='fi-FI'; PL='pl-PL'; CZ='cs-CZ'; HU='hu-HU'; RO='ro-RO'
    GR='el-GR'; TR='tr-TR'; IL='he-IL'; IN='en-IN'; TH='th-TH'; MY='ms-MY'; ID='id-ID'
    PH='en-PH'; VN='vi-VN'; BR='pt-BR'; MX='es-MX'; AR='es-AR'; CL='es-CL'; ZA='en-ZA'
    AE='ar-AE'; RU='ru-RU'; UA='uk-UA'
}

$script:IanaWindowsTimeZoneMap = @{
    'America/New_York'='Eastern Standard Time'; 'America/Detroit'='Eastern Standard Time'
    'America/Toronto'='Eastern Standard Time'; 'America/Montreal'='Eastern Standard Time'
    'America/Indiana/Indianapolis'='US Eastern Standard Time'; 'America/Chicago'='Central Standard Time'
    'America/Winnipeg'='Central Standard Time'; 'America/Denver'='Mountain Standard Time'
    'America/Edmonton'='Mountain Standard Time'; 'America/Phoenix'='US Mountain Standard Time'
    'America/Los_Angeles'='Pacific Standard Time'; 'America/Vancouver'='Pacific Standard Time'
    'America/Anchorage'='Alaskan Standard Time'; 'Pacific/Honolulu'='Hawaiian Standard Time'
    'America/Halifax'='Atlantic Standard Time'; 'America/St_Johns'='Newfoundland Standard Time'
    'America/Regina'='Canada Central Standard Time'; 'America/Whitehorse'='Yukon Standard Time'
    'America/Mexico_City'='Central Standard Time (Mexico)'; 'America/Cancun'='Eastern Standard Time (Mexico)'
    'America/Tijuana'='Pacific Standard Time (Mexico)'; 'America/Sao_Paulo'='E. South America Standard Time'
    'America/Argentina/Buenos_Aires'='Argentina Standard Time'; 'America/Santiago'='Pacific SA Standard Time'
    'Europe/London'='GMT Standard Time'; 'Europe/Dublin'='GMT Standard Time'
    'Europe/Berlin'='W. Europe Standard Time'; 'Europe/Paris'='Romance Standard Time'
    'Europe/Amsterdam'='W. Europe Standard Time'; 'Europe/Brussels'='Romance Standard Time'
    'Europe/Madrid'='Romance Standard Time'; 'Europe/Rome'='W. Europe Standard Time'
    'Europe/Lisbon'='GMT Standard Time'
    'Europe/Zurich'='W. Europe Standard Time'; 'Europe/Vienna'='W. Europe Standard Time'
    'Europe/Stockholm'='W. Europe Standard Time'; 'Europe/Oslo'='W. Europe Standard Time'
    'Europe/Copenhagen'='Romance Standard Time'; 'Europe/Helsinki'='FLE Standard Time'
    'Europe/Warsaw'='Central European Standard Time'; 'Europe/Prague'='Central Europe Standard Time'
    'Europe/Budapest'='Central Europe Standard Time'; 'Europe/Bucharest'='GTB Standard Time'
    'Europe/Athens'='GTB Standard Time'; 'Europe/Istanbul'='Turkey Standard Time'
    'Europe/Moscow'='Russian Standard Time'; 'Europe/Kyiv'='FLE Standard Time'
    'Asia/Tokyo'='Tokyo Standard Time'; 'Asia/Seoul'='Korea Standard Time'
    'Asia/Singapore'='Singapore Standard Time'; 'Asia/Taipei'='Taipei Standard Time'
    'Asia/Hong_Kong'='China Standard Time'; 'Asia/Shanghai'='China Standard Time'
    'Asia/Manila'='Singapore Standard Time'; 'Asia/Kuala_Lumpur'='Singapore Standard Time'
    'Asia/Bangkok'='SE Asia Standard Time'; 'Asia/Ho_Chi_Minh'='SE Asia Standard Time'
    'Asia/Jakarta'='SE Asia Standard Time'; 'Asia/Kolkata'='India Standard Time'
    'Asia/Dubai'='Arabian Standard Time'; 'Asia/Jerusalem'='Israel Standard Time'
    'Asia/Riyadh'='Arab Standard Time'; 'Asia/Karachi'='Pakistan Standard Time'
    'Asia/Dhaka'='Bangladesh Standard Time'; 'Asia/Colombo'='Sri Lanka Standard Time'
    'Australia/Sydney'='AUS Eastern Standard Time'; 'Australia/Melbourne'='AUS Eastern Standard Time'
    'Australia/Brisbane'='E. Australia Standard Time'; 'Australia/Perth'='W. Australia Standard Time'
    'Australia/Adelaide'='Cen. Australia Standard Time'; 'Australia/Darwin'='AUS Central Standard Time'
    'Pacific/Auckland'='New Zealand Standard Time'; 'Pacific/Fiji'='Fiji Standard Time'
    'Africa/Johannesburg'='South Africa Standard Time'; 'Africa/Cairo'='Egypt Standard Time'
}

$script:CountryDefaultTimeZone = @{
    US='America/New_York'; GB='Europe/London'; JP='Asia/Tokyo'; KR='Asia/Seoul'; TW='Asia/Taipei'
    HK='Asia/Hong_Kong'; SG='Asia/Singapore'; DE='Europe/Berlin'; FR='Europe/Paris'
    CA='America/Toronto'; AU='Australia/Sydney'; NZ='Pacific/Auckland'; IE='Europe/Dublin'
    NL='Europe/Amsterdam'; CH='Europe/Zurich'; AT='Europe/Vienna'; ES='Europe/Madrid'
    IT='Europe/Rome'; PT='Europe/Lisbon'; SE='Europe/Stockholm'; NO='Europe/Oslo'
    DK='Europe/Copenhagen'; FI='Europe/Helsinki'; PL='Europe/Warsaw'; CZ='Europe/Prague'
    BR='America/Sao_Paulo'; MX='America/Mexico_City'; IN='Asia/Kolkata'; TH='Asia/Bangkok'
    MY='Asia/Kuala_Lumpur'; ID='Asia/Jakarta'; PH='Asia/Manila'; VN='Asia/Ho_Chi_Minh'
    AE='Asia/Dubai'; ZA='Africa/Johannesburg'; IL='Asia/Jerusalem'; RU='Europe/Moscow'
    CN='Asia/Shanghai'
}

$script:CountryGeoId = @{
    US=244; GB=242; JP=122; KR=134; TW=237; HK=104; SG=215; DE=94; FR=84; CA=39; AU=12
    NZ=163; IE=68; NL=151; CH=223; AT=14; BE=21; ES=217; IT=118; PT=193; SE=221; NO=177; CN=45
    DK=61; FI=77; PL=191; CZ=75; HU=109; RO=200; GR=98; TR=235; IL=117; IN=113; TH=227
    MY=137; ID=105; PH=189; VN=251; BR=32; MX=148; AR=11; CL=46; ZA=209; AE=2; RU=203; UA=241
}

function Get-RegionInfo {
    $info = $null
    try {
        $raw = & curl.exe -s --max-time 8 'https://ipinfo.io/json' 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) { $info = ($raw | ConvertFrom-Json -ErrorAction Stop) }
    } catch {}
    $country = if ($info -and $info.country) { ([string]$info.country).ToUpperInvariant() } else { '' }
    $iana = if ($info -and $info.timezone) { [string]$info.timezone } else { '' }
    $ip = if ($info -and $info.ip) { [string]$info.ip } else { '' }
    $org = if ($info -and $info.org) { [string]$info.org } else { '' }
    # A fallback must supply one complete observation, never a mix of two exits.
    if (-not $country -or -not $ip) {
        $country = ''; $ip = ''; $iana = ''; $org = ''
        $fallback = Get-Egress
        $country = $fallback.loc; $ip = $fallback.ip
    }
    if (-not $iana) {
        try {
            $timezone = & curl.exe -s --max-time 5 'https://ipinfo.io/timezone' 2>$null
            if ($LASTEXITCODE -eq 0 -and $timezone -match '^[A-Za-z_]+/[A-Za-z0-9_+/-]+$') { $iana = $timezone.Trim() }
        } catch {}
    }
    if (-not $iana -and $country) { $iana = $script:CountryDefaultTimeZone[$country] }
    $culture = $script:RegionCultureMap[$country]
    if (-not $culture) {
        $culture = 'en-US'
        Write-Warning "国家 $country 没有地区格式映射，使用 en-US。"
    }
    $tzWindows = if ($iana) { $script:IanaWindowsTimeZoneMap[$iana] } else { '' }
    if (-not $tzWindows) {
        Write-Warning "无法将 IANA 时区 '$iana' 映射为 Windows 时区；保持当前时区不变。"
    }
    return [pscustomobject]@{
        country=$country; ip=$ip; exit_ip=$ip; org=$org; asn=$org; tz_windows=$tzWindows; tz_iana=$iana
        culture=$culture; updated_at=(Get-Date).ToString('o')
    }
}

function Save-RegionInfo($region, [string]$path) {
    $exitIp = if ($region.exit_ip) { [string]$region.exit_ip } else { [string]$region.ip }
    $lockedAt = if ($region.locked_at -is [datetime] -or $region.locked_at -is [datetimeoffset]) { $region.locked_at.ToString('o') } elseif ($region.locked_at) { [string]$region.locked_at } else { (Get-Date).ToString('o') }
    $parsedIp = $null
    if (-not [System.Net.IPAddress]::TryParse($exitIp, [ref]$parsedIp) -or $region.country -notmatch '^[A-Za-z]{2}$') {
        throw '出口IP或国家无效，未写入基准'
    }
    $json = [pscustomobject]@{
        exit_ip=$parsedIp.ToString(); country=([string]$region.country).ToUpperInvariant(); tz_iana=$region.tz_iana; tz_windows=$region.tz_windows
        culture=$region.culture; locked_at=$lockedAt; asn=$region.asn
    } | ConvertTo-Json
    # Same-directory atomic replacement keeps a partial JSON write out of the guard.
    $temp = "$path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [System.IO.File]::WriteAllText($temp, $json, (New-Object System.Text.UTF8Encoding -ArgumentList $true))
        if ([System.IO.File]::Exists($path)) {
            $backup = "$temp.bak"
            [System.IO.File]::Replace($temp, $path, $backup)
            [System.IO.File]::Delete($backup)
        }
        else { [System.IO.File]::Move($temp, $path) }
    } finally { if ([System.IO.File]::Exists($temp)) { [System.IO.File]::Delete($temp) } }

}

function Protect-ExitIp([string]$ip) {
    if ($ip -match '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$') { return "$($Matches[1]).$($Matches[2]).*.*" }
    if ($ip -match ':') { return (($ip -split ':')[0..([Math]::Min(1, ($ip -split ':').Count - 1))] -join ':') + ':*' }
    return '未知'
}

function Test-RegionEgressMatch([string]$currentIp, [string]$currentCountry, $lockedRegion) {
    $expectedIp = if ($lockedRegion) { [string]$lockedRegion.exit_ip } else { '' }
    $expectedCountry = if ($lockedRegion) { ([string]$lockedRegion.country).ToUpperInvariant() } else { '' }
    $currentAddress = $null; $expectedAddress = $null
    $validCurrent = [System.Net.IPAddress]::TryParse($currentIp, [ref]$currentAddress)
    $validExpected = [System.Net.IPAddress]::TryParse($expectedIp, [ref]$expectedAddress)
    $ipOk = $validCurrent -and $validExpected -and $currentAddress.Equals($expectedAddress)
    $countryOk = $currentCountry -match '^[A-Za-z]{2}$' -and $expectedCountry -match '^[A-Z]{2}$' -and (([string]$currentCountry).ToUpperInvariant() -ceq $expectedCountry)
    $reason = ''
    if (-not $lockedRegion -or -not $validExpected -or $expectedCountry -notmatch '^[A-Z]{2}$') { $reason = '基准环境缺少锁定出口IP或国家' }
    elseif (-not $validCurrent -or $currentCountry -notmatch '^[A-Za-z]{2}$') { $reason = '无法获取当前出口IP或国家' }
    elseif (-not $ipOk) { $reason = "出口IP偏离：当前 $(Protect-ExitIp $currentIp)，期望 $(Protect-ExitIp $expectedIp)" }
    elseif (-not $countryOk) { $reason = "出口国家偏离：当前 $currentCountry，期望 $expectedCountry" }
    return [pscustomobject]@{ passed=[bool]($ipOk -and $countryOk); ip_ok=[bool]$ipOk; country_ok=[bool]$countryOk; reason=$reason }
}

function Get-EgressMismatchDecision([int]$previousCount, [bool]$isMismatch, [int]$threshold = 2) {
    $count = if ($isMismatch) { $previousCount + 1 } else { 0 }
    return [pscustomobject]@{ count=$count; blocked=($count -ge $threshold) }
}

function Apply-RegionUserSettings($region) {
    try { Set-Culture -CultureInfo $region.culture -ErrorAction Stop; $true } catch {
        Write-Warning "无法设置用户地区格式 $($region.culture): $($_.Exception.Message)"
        $false
    }
}

function Apply-RegionSystemSettings($region) {
    $results = @()
    if ($region.tz_windows) {
        try { Set-TimeZone -Id $region.tz_windows -ErrorAction Stop; $results += '时区已设置' } catch { $results += "时区设置失败: $($_.Exception.Message)" }
    }
    $geoId = $script:CountryGeoId[$region.country]
    if ($geoId) {
        try { Set-WinHomeLocation -GeoId $geoId -ErrorAction Stop; $results += '区域位置已设置' } catch { $results += "区域位置设置失败: $($_.Exception.Message)" }
    }
    try { Set-WinSystemLocale -SystemLocale $region.culture -ErrorAction Stop; $results += '系统区域格式已设置' } catch { $results += "系统区域格式设置失败: $($_.Exception.Message)" }
    return $results
}

function Get-Egress {
    $ip = ''; $loc = ''
    try {
        $trace = & curl.exe -s --max-time 8 "https://www.cloudflare.com/cdn-cgi/trace" 2>$null
        if ($LASTEXITCODE -eq 0 -and $trace) {
            $ip  = (($trace -split "`n" | Where-Object { $_ -like 'ip=*' } | Select-Object -First 1) -replace '^ip=','').Trim()
            $loc = ((($trace -split "`n" | Where-Object { $_ -like 'loc=*' } | Select-Object -First 1) -replace '^loc=','').Trim()).ToUpperInvariant()
        }
    } catch {}
    return @{ ip = $ip; loc = $loc }
}


# Require one recognized result for each check. Missing/duplicate/unknown states block startup.
function Test-CheckReport([string[]]$lines) {
    $expected = @('代理内核','TUN网卡','出口IP','IP一致','时区','地区','IPv6','DNS','WebRTC','保镖','规则置顶','客户端语言','ASN属性','生态可达性')
    $seen = @{}; $problems = @()
    foreach ($line in $lines) {
        $kv = $line -split '=', 2
        if ($kv.Count -ne 2 -or $expected -notcontains $kv[0]) { continue }
        if ($seen.ContainsKey($kv[0])) { $problems += "重复检查项: $($kv[0])"; continue }
        $seen[$kv[0]] = $true
        $state = ($kv[1] -split ':', 2)[0]
        if ($state -notin @('ok','warn','info')) { $problems += $line }
    }
    foreach ($name in $expected) { if (-not $seen.ContainsKey($name)) { $problems += "缺少检查项: $name" } }
    return [pscustomobject]@{ passed=($problems.Count -eq 0); errors=@($problems) }
}
