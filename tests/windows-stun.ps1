# Protocol fixtures + loopback UDP. Never contacts a public STUN server.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'windows/region-functions.ps1')
. (Join-Path $root 'windows/stun-functions.ps1')
$passed=0
function Assert([bool]$ok,[string]$message) { if(-not $ok){throw $message};$script:passed++ }
function New-Response([byte[]]$transaction,[byte[]]$attributes,[int]$kind=0x0101) {
    $n=$attributes.Length
    return [byte[]](@([byte]($kind -shr 8),[byte]($kind -band 255),[byte]($n -shr 8),[byte]($n -band 255),0x21,0x12,0xA4,0x42)+$transaction+$attributes)
}
$txn=[byte[]](1,2,3,4,5,6,7,8,9,10,11,12)
# XOR-MAPPED-ADDRESS encodes 203.0.113.9 with the magic cookie.
$xor=[byte[]](0,0x20,0,8,0,1,0x20,0,234,18,213,75)
$plain=[byte[]](0,1,0,8,0,1,0,1,203,0,113,9)
$valid=New-Response $txn $xor
$r=Read-StunResponse $valid $txn
Assert ($r.status -eq 'ok' -and $r.ip -eq '203.0.113.9') 'XOR IPv4 decode failed'
Assert ((Read-StunResponse (New-Response $txn $plain) $txn).ip -eq '203.0.113.9') 'Plain IPv4 decode failed'
$otherPlain=[byte[]](0,1,0,8,0,1,0,1,192,0,2,1)
Assert ((Read-StunResponse (New-Response $txn ($otherPlain+$xor)) $txn).ip -eq '203.0.113.9') 'XOR address did not take precedence'
$padding=[byte[]](0x80,0x22,0,1,65,0,0,0)
Assert ((Read-StunResponse (New-Response $txn ($padding+$xor)) $txn).status -eq 'ok') 'Padded unknown attribute broke parsing'
$bytes=[Net.IPAddress]::Parse('2001:db8::9').GetAddressBytes();$mask=[byte[]](0x21,0x12,0xA4,0x42)+$txn
for($i=0;$i -lt 16;$i++){$bytes[$i]=$bytes[$i] -bxor $mask[$i]}
$attr6=[byte[]](0,0x20,0,20,0,2,0,1)+$bytes
Assert ((Read-StunResponse (New-Response $txn $attr6) $txn).ip -eq '2001:db8::9') 'XOR IPv6 parser failed'
Assert ((Read-StunResponse ([byte[]](0,1)) $txn).detail -eq 'header_truncated') 'Short header accepted'
$bad=$valid.Clone();$bad[0]=0
Assert ((Read-StunResponse $bad $txn).detail -eq 'not_binding_response') 'Request accepted as response'
$bad=$valid.Clone();$bad[4]=0
Assert ((Read-StunResponse $bad $txn).detail -eq 'bad_magic_cookie') 'Bad cookie accepted'
$bad=$valid.Clone();$bad[8]=0
Assert ((Read-StunResponse $bad $txn).detail -eq 'transaction_mismatch') 'Unrelated transaction accepted'
$bad=$valid.Clone();$bad[3]=16
Assert ((Read-StunResponse $bad $txn).detail -eq 'message_length_mismatch') 'Wrong message length accepted'
$bad=$valid.Clone();$bad[23]=12
Assert ((Read-StunResponse $bad $txn).detail -eq 'attribute_value_truncated') 'Truncated attribute accepted'
Assert ((Read-StunResponse (New-Response $txn ([byte[]](0,0x20,0,4,0,1,0,1))) $txn).detail -eq 'mapped_address_length') 'Bad address length accepted'
Assert ((Read-StunResponse (New-Response $txn ([byte[]](0,0x20,0,4,0,7,0,1))) $txn).status -eq 'unsupported_address') 'Unknown family was mistaken for timeout'
Assert ((Read-StunResponse (New-Response $txn @()) $txn).detail -eq 'no_mapped_address') 'Missing mapped address accepted'
$err=[byte[]](0,9,0,4,0,0,4,1)
Assert ((Read-StunResponse (New-Response $txn $err 0x0111) $txn).detail -eq 'server_error_401') 'STUN server error mistaken for timeout'
$ok=[pscustomobject]@{status='ok';ip='203.0.113.9'}
$timeout=[pscustomobject]@{status='timeout';ip=''}
Assert ((Get-StunAssessment @($ok,$ok,$ok,$ok) '203.0.113.9').code -eq 'ok') 'All successful observations rejected'
Assert ((Get-StunAssessment @($ok,$timeout) '203.0.113.9').code -eq 'warn') 'Partial result falsely passed'
Assert ((Get-StunAssessment @($timeout,$timeout) '203.0.113.9').code -eq 'warn') 'No replies falsely passed'
Assert ((Get-StunAssessment @() '203.0.113.9').code -eq 'warn') 'Empty result falsely passed'
Assert ((Get-StunAssessment @($ok) '').code -eq 'warn') 'Unknown HTTPS exit falsely passed'
Assert ((Get-StunAssessment @($ok,$timeout) '192.0.2.1').code -eq 'fail') 'Exit mismatch ignored'
$fake=[pscustomobject]@{server='test';port=3478;status='ok';detail='parsed';ip='203.0.113.9';attempts=1;sent_bytes=20;received_bytes=32;ignored_packets=0;elapsed_ms=5}
$line=Format-StunDiagnostics @($fake)
Assert ($line -match 'received=32B' -and $line -notmatch '203\.0\.113\.9') 'Diagnostic counter missing or full IP leaked'
# Mock DNS stage without making DNS requests.
$originalResolver=${function:Resolve-StunIPv4}
foreach($dnsStatus in @('dns_error','dns_timeout','dns_no_ipv4')) {
    function Resolve-StunIPv4 { return @{status=$dnsStatus;detail='synthetic';address=$null} }
    $r=Invoke-StunProbe 'test.invalid' 3478 300
    Assert ($r.status -eq $dnsStatus -and $r.sent_bytes -eq 0) 'DNS failure was conflated with network timeout'
}
Set-Item Function:Resolve-StunIPv4 $originalResolver

function Start-LoopbackResponder([string]$mode) {
    $job=Start-Job -ArgumentList $mode -ScriptBlock {
        param($mode)
        $udp=New-Object Net.Sockets.UdpClient -ArgumentList 0
        try {
            $udp.Client.ReceiveTimeout=5000
            Write-Output $udp.Client.LocalEndPoint.Port
            if($mode -eq 'silent'){Start-Sleep -Seconds 3;return}
            $remote=New-Object Net.IPEndPoint -ArgumentList ([Net.IPAddress]::Any),0
            $req=$udp.Receive([ref]$remote)
            if($mode -eq 'dropfirst'){$req=$udp.Receive([ref]$remote)}
            $attributes=[byte[]](0,0x20,0,8,0,1,0x20,0,234,18,213,75)
            $response=[byte[]](1,1,0,12,0x21,0x12,0xA4,0x42)+$req[8..19]+$attributes
            if($mode -eq 'invalid'){$response[4]=0}
            [void]$udp.Send($response,$response.Length,$remote)
            # Keep socket alive so subsequent sends don't become ICMP port-unreachable.
            if($mode -eq 'invalid'){Start-Sleep -Seconds 3}
        } finally {$udp.Close()}
    }
    for($i=0;$i -lt 200;$i++) {
        $port=@(Receive-Job $job -Keep | Where-Object {$_ -is [int]}) | Select-Object -First 1
        if($port){return @{job=$job;port=$port}}
        if($job.State -in @('Failed','Stopped','Completed')){throw 'Loopback responder failed before ready'}
        Start-Sleep -Milliseconds 50
    }
    Stop-Job $job;Remove-Job $job -Force;throw 'Loopback responder startup deadline'
}
foreach($mode in @('valid','dropfirst','invalid','silent')) {
    $server=Start-LoopbackResponder $mode
    try {
        $r=Invoke-StunProbe '127.0.0.1' $server.port 900 500
        if($mode -eq 'valid'){Assert ($r.status -eq 'ok' -and $r.received_bytes -eq 32 -and $r.sent_bytes -eq 20) 'Real UDP success failed'}
        elseif($mode -eq 'dropfirst'){Assert ($r.status -eq 'ok' -and $r.attempts -eq 2 -and $r.sent_bytes -eq 40) 'Lost first request was not retransmitted'}
        elseif($mode -eq 'invalid'){Assert ($r.status -eq 'invalid_response' -and $r.received_bytes -gt 0 -and $r.detail -eq 'bad_magic_cookie') 'Received malformed reply was labeled no response'}
        else{Assert ($r.status -eq 'timeout' -and $r.received_bytes -eq 0 -and $r.sent_bytes -eq 40) 'No reply counters/status incorrect'}
        Assert ($r.elapsed_ms -lt 2500) 'Probe exceeded isolated time budget'
    } finally {Stop-Job $server.job -ErrorAction SilentlyContinue;Remove-Job $server.job -Force -ErrorAction SilentlyContinue}
}
Write-Host "PASS: $passed STUN assertions"
