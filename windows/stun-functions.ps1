# Unauthenticated UDP STUN diagnostics; not a browser ICE/WebRTC test.
function Read-StunResponse([byte[]]$data, [byte[]]$transaction) {
    $bad = @{ status='invalid_response'; ip=''; detail='header_truncated' }
    if ($data.Length -lt 20 -or $transaction.Length -ne 12) { return $bad }
    $kind = ([int]$data[0] -shl 8) -bor $data[1]
    if ($kind -notin @(0x0101,0x0111)) { $bad.detail='not_binding_response'; return $bad }
    if (($data[4..7] -join ',') -ne '33,18,164,66') { $bad.detail='bad_magic_cookie'; return $bad }
    for ($i=0; $i -lt 12; $i++) {
        if ($data[8+$i] -ne $transaction[$i]) { $bad.detail='transaction_mismatch'; return $bad }
    }
    $length = ([int]$data[2] -shl 8) -bor $data[3]
    if ($length % 4 -ne 0 -or $data.Length -ne 20+$length) { $bad.detail='message_length_mismatch'; return $bad }
    $mapped=''; $xorMapped=''; $errorCode=0; $unsupported=$false
    $position=20
    while ($position -lt $data.Length) {
        if ($position+4 -gt $data.Length) { $bad.detail='attribute_header_truncated'; return $bad }
        $type=([int]$data[$position] -shl 8) -bor $data[$position+1]
        $size=([int]$data[$position+2] -shl 8) -bor $data[$position+3]
        $padded=$size+((4-$size%4)%4)
        if ($position+4+$padded -gt $data.Length) { $bad.detail='attribute_value_truncated'; return $bad }
        if ($type -in @(0x0020,0x0001)) {
            if ($size -lt 4) { $bad.detail='mapped_address_truncated'; return $bad }
            $family=$data[$position+5]
            $addressSize=if ($family -eq 1) { 4 } elseif ($family -eq 2) { 16 } else { 0 }
            if (-not $addressSize) { $unsupported=$true }
            elseif ($size -ne 4+$addressSize) { $bad.detail='mapped_address_length'; return $bad }
            else {
                $bytes=New-Object byte[] $addressSize
                $mask=[byte[]](0x21,0x12,0xA4,0x42)+$transaction
                for ($i=0; $i -lt $addressSize; $i++) {
                    $bytes[$i]=$data[$position+8+$i]
                    if ($type -eq 0x0020) { $bytes[$i]=$bytes[$i] -bxor $mask[$i] }
                }
                $ip=(New-Object System.Net.IPAddress -ArgumentList (,$bytes)).ToString()
                if ($type -eq 0x0020) { $xorMapped=$ip } else { $mapped=$ip }
            }
        } elseif ($type -eq 0x0009) {
            if ($size -lt 4) { $bad.detail='error_code_truncated'; return $bad }
            $errorCode=([int]$data[$position+6] -band 7)*100+$data[$position+7]
        }
        $position+=4+$padded
    }
    if ($kind -eq 0x0111) { return @{status='stun_error';ip='';detail="server_error_$errorCode"} }
    $ip=if ($xorMapped) { $xorMapped } else { $mapped }
    if ($ip) { return @{status='ok';ip=$ip;detail='binding_address_parsed'} }
    if ($unsupported) { return @{status='unsupported_address';ip='';detail='unknown_address_family'} }
    return @{status='invalid_response';ip='';detail='no_mapped_address'}
}

function Resolve-StunIPv4([string]$server, [int]$timeoutMs=1500) {
    try {
        $task=[System.Net.Dns]::GetHostAddressesAsync($server)
        if (-not $task.Wait($timeoutMs)) { return @{status='dns_timeout';address=$null;detail='dns_deadline'} }
        $address=$task.Result | Where-Object { $_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork } | Select-Object -First 1
        if (-not $address) { return @{status='dns_no_ipv4';address=$null;detail='no_ipv4_address'} }
        return @{status='ok';address=$address;detail='resolved'}
    } catch { return @{status='dns_error';address=$null;detail='dns_lookup_failed'} }
}

function Get-StunSocketError($record) {
    $exception=$record.Exception
    while ($exception.InnerException) { $exception=$exception.InnerException }
    if ($exception -is [Net.Sockets.SocketException]) { return [string]$exception.SocketErrorCode }
    return 'operation_failed'
}

function Invoke-StunProbe([string]$server,[int]$port,[int]$timeoutMs=4000,[int]$dnsTimeoutMs=1500) {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $result=[pscustomobject]@{
        server=$server;port=$port;status='config_error';detail='invalid_probe_parameters';ip=''
        attempts=0;sent_bytes=0;received_bytes=0;ignored_packets=0;elapsed_ms=0
    }
    $udp=$null
    try {
        if (-not $server -or $port -lt 1 -or $port -gt 65535 -or $timeoutMs -lt 100 -or $dnsTimeoutMs -lt 1) { return $result }
        $dns=Resolve-StunIPv4 $server $dnsTimeoutMs
        if ($dns.status -ne 'ok') { $result.status=$dns.status;$result.detail=$dns.detail;return $result }
        try {
            $udp=New-Object Net.Sockets.UdpClient -ArgumentList ([Net.Sockets.AddressFamily]::InterNetwork)
            $udp.Connect($dns.address,$port)
        } catch { $result.status='socket_error';$result.detail=Get-StunSocketError $_;return $result }
        $txn=New-Object byte[] 12
        $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($txn) } finally { $rng.Dispose() }
        $request=[byte[]](0,1,0,0,0x21,0x12,0xA4,0x42)+$txn
        $networkClock=[Diagnostics.Stopwatch]::StartNew()
        $lastInvalid=$null
        # One retransmission, same socket and transaction; fixed total network deadline.
        $firstWindow=[int][Math]::Max(1,[Math]::Floor($timeoutMs/3))
        for ($attempt=0; $attempt -lt 2; $attempt++) {
            $remaining=$timeoutMs-[int]$networkClock.ElapsedMilliseconds
            if ($remaining -le 0) { break }
            try {
                $result.attempts++
                $udp.Client.SendTimeout=[int][Math]::Max(1,$remaining)
                $result.sent_bytes+=$udp.Send($request,$request.Length)
            } catch { $result.status='send_error';$result.detail=Get-StunSocketError $_;return $result }
            $until=if ($attempt -eq 0) { $firstWindow } else { $timeoutMs }
            while ($networkClock.ElapsedMilliseconds -lt $until) {
                $udp.Client.ReceiveTimeout=[int][Math]::Max(1,$until-$networkClock.ElapsedMilliseconds)
                $remote=New-Object Net.IPEndPoint -ArgumentList ([Net.IPAddress]::Any),0
                try { $data=$udp.Receive([ref]$remote) }
                catch {
                    $errorCode=Get-StunSocketError $_
                    if ($errorCode -in @('TimedOut','WouldBlock')) { break }
                    $result.status='receive_error';$result.detail=$errorCode;return $result
                }
                $result.received_bytes+=$data.Length
                $parsed=Read-StunResponse $data $txn
                if ($parsed.status -in @('ok','stun_error','unsupported_address')) {
                    $result.status=$parsed.status;$result.ip=$parsed.ip;$result.detail=$parsed.detail;return $result
                }
                $lastInvalid=$parsed;$result.ignored_packets++
            }
        }
        if ($lastInvalid) { $result.status='invalid_response';$result.detail=$lastInvalid.detail }
        else { $result.status='timeout';$result.detail='no_datagram_before_deadline' }
        return $result
    } catch { $result.status='probe_error';$result.detail='unexpected_probe_failure';return $result }
    finally {
        if ($udp) { $udp.Close() }
        $result.elapsed_ms=[int]$clock.ElapsedMilliseconds
    }
}

function Get-StunStatusLabel([string]$status) {
    $labels=@{
        ok='收到有效地址'; dns_error='DNS解析失败'; dns_timeout='DNS超时'; dns_no_ipv4='DNS无IPv4结果'
        socket_error='套接字初始化失败'; send_error='发送失败'; receive_error='接收错误'
        timeout='接收超时'; invalid_response='回包无效'; stun_error='STUN服务端拒绝'
        unsupported_address='地址类型不支持'; config_error='探针参数错误'; probe_error='探针内部异常'
    }
    if ($labels.ContainsKey($status)) { return $labels[$status] }
    return '未知状态'
}

function Get-StunAssessment($results,[string]$exitIp) {
    $items=@($results)
    $expected=$null
    if (-not [Net.IPAddress]::TryParse($exitIp,[ref]$expected)) { return @{code='warn';detail='HTTPS出口未知，无法比较；见STUN诊断'} }
    $ok=@($items | Where-Object { $_.status -eq 'ok' })
    $different=@($ok | Where-Object { $address=$null; -not [Net.IPAddress]::TryParse($_.ip,[ref]$address) -or -not $expected.Equals($address) })
    if ($different.Count) { return @{code='fail';detail='UDP出口与HTTPS出口不同，请核实路由；见STUN诊断'} }
    if ($items.Count -gt 0 -and $ok.Count -eq $items.Count) { return @{code='ok';detail="$($ok.Count)/$($items.Count) STUN出口一致(仅UDP探针)"} }
    $issues = @($items | Where-Object { $_.status -ne 'ok' } | Group-Object status | ForEach-Object { "$(Get-StunStatusLabel $_.Name)×$($_.Count)" }) -join '、'
    return @{code='warn';detail="$($ok.Count)/$($items.Count)已确认；$issues；见STUN诊断"}
}

function Format-StunDiagnostics($results) {
    foreach ($r in $results) {
        $masked=if ($r.ip) { Protect-ExitIp $r.ip } else { '-' }
        "$($r.server):$($r.port) status=$($r.status)($(Get-StunStatusLabel $r.status)) attempts=$($r.attempts) sent=$($r.sent_bytes)B received=$($r.received_bytes)B ignored=$($r.ignored_packets) elapsed=$($r.elapsed_ms)ms detail=$($r.detail) mapped=$masked"
    }
}
