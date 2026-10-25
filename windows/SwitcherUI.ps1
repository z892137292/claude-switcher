# Claude 账号切换器 - Windows 界面 (WPF, Beta)
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$BASE = "$env:USERPROFILE\.claude-switcher"
$CORE = "$BASE\claude-switch.ps1"

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude 账号切换器" Width="540" Height="980" ResizeMode="CanResize"
        WindowStartupLocation="CenterScreen" Background="#FF12141D" Foreground="White">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Orientation="Horizontal" Grid.Row="0" Margin="0,0,0,14">
            <Border Width="44" Height="44" CornerRadius="12">
                <Border.Background>
                    <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                        <GradientStop Color="#FF6366F1" Offset="0"/><GradientStop Color="#FF9333EA" Offset="1"/>
                    </LinearGradientBrush>
                </Border.Background>
                <TextBlock Text="盾" HorizontalAlignment="Center" VerticalAlignment="Center" FontSize="20" Foreground="White"/>
            </Border>
            <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
                <TextBlock Text="Claude 账号切换器" FontSize="18" FontWeight="Bold"/>
                <TextBlock Text="安全检查 · 切换 · 启动" FontSize="11" Foreground="#8AFFFFFF"/>
            </StackPanel>
            <Border x:Name="StatusPill" Margin="60,0,0,0" Padding="12,5" CornerRadius="12" Background="#2E22C55E" VerticalAlignment="Center">
                <TextBlock x:Name="StatusText" Text="检查中" FontSize="11" FontWeight="Bold" Foreground="#FFFB923C"/>
            </Border>
        </StackPanel>

        <Border Grid.Row="1" CornerRadius="12" Background="#0DFFFFFF" BorderBrush="#14FFFFFF" BorderThickness="1" Padding="10" Margin="0,0,0,10">
            <StackPanel>
                <TextBlock Text="出口IP锁定地区" FontSize="11" Foreground="#80FFFFFF"/>
                <TextBlock x:Name="RegionText" Text="尚未同步" FontSize="13" FontWeight="Bold" Margin="0,4,0,0"/>
            </StackPanel>
        </Border>

        <Border Grid.Row="2" CornerRadius="12" Background="#0DFFFFFF" BorderBrush="#14FFFFFF" BorderThickness="1" Padding="4">
            <ListBox x:Name="CheckList" Background="Transparent" BorderThickness="0" Foreground="#E6FFFFFF" FontSize="13">
                <ListBox.ItemTemplate>
                    <DataTemplate>
                        <Grid Margin="6,6" Width="380">
                            <TextBlock Text="{Binding Name}" VerticalAlignment="Center"/>
                            <TextBlock Text="{Binding Detail}" HorizontalAlignment="Right" Margin="110,0,26,0" Foreground="#73FFFFFF" FontSize="11" TextTrimming="CharacterEllipsis"/>
                            <TextBlock Text="{Binding Icon}" HorizontalAlignment="Right" Foreground="{Binding Color}" FontSize="14" FontWeight="Bold"/>
                        </Grid>
                    </DataTemplate>
                </ListBox.ItemTemplate>
            </ListBox>
        </Border>

        <StackPanel Grid.Row="3" Margin="0,14,0,0">
            <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                <TextBlock Text="当前账号" FontSize="11" Foreground="#80FFFFFF" VerticalAlignment="Center"/>
                <Border Margin="6,0,0,0" Padding="10,3" CornerRadius="10" Background="#4D6366F1">
                    <TextBlock x:Name="CurrentAccount" Text="?" FontSize="11" FontWeight="Bold" Foreground="#FFA5B4FC"/>
                </Border>
            </StackPanel>
            <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="10"/><ColumnDefinition/></Grid.ColumnDefinitions>
                <Button x:Name="BtnA" Grid.Column="0" Content="账号 A" Height="52" FontSize="15" FontWeight="Bold"
                        Foreground="White" Background="#7A6366F1" BorderThickness="0" Cursor="Hand"/>
                <Button x:Name="BtnB" Grid.Column="2" Content="账号 B" Height="52" FontSize="15" FontWeight="Bold"
                        Foreground="White" Background="#14FFFFFF" BorderBrush="#26FFFFFF" Cursor="Hand"/>
            </Grid>
            <TextBlock x:Name="ActionHint" Text="" FontSize="11" Foreground="#80FFFFFF" Margin="0,8,0,0" TextWrapping="Wrap"/>
        </StackPanel>

        <StackPanel Grid.Row="4">
            <TextBlock x:Name="Banner" Text="" FontSize="12" Foreground="#FFF87171" Margin="0,12,0,6" TextWrapping="Wrap"/>
            <WrapPanel HorizontalAlignment="Center">
                <Button x:Name="BtnFix" Content="一键修复" Padding="18,8" Margin="0,0,10,0" FontWeight="Bold" Foreground="White" BorderThickness="0" Cursor="Hand">
                    <Button.Background>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                            <GradientStop Color="#FF6366F1" Offset="0"/><GradientStop Color="#FF9333EA" Offset="1"/>
                        </LinearGradientBrush>
                    </Button.Background>
                </Button>
                <Button x:Name="BtnRefresh" Content="重新检查" Padding="18,8" FontWeight="Bold" Foreground="White" Background="#1AFFFFFF" BorderThickness="0" Cursor="Hand"/>
                <Button x:Name="BtnRegion" Content="同步地区" Padding="12,8" Margin="8,0,0,0" FontWeight="Bold" Foreground="White" Background="#1AFFFFFF" BorderThickness="0" Cursor="Hand"/>
                <Button x:Name="BtnDiagnostic" Content="复制诊断报告" Padding="12,8" Margin="8,0,0,0" FontWeight="Bold" Foreground="White" Background="#1AFFFFFF" BorderThickness="0" Cursor="Hand"/>
                <Button x:Name="BtnLogs" Content="打开日志" Padding="12,8" Margin="8,0,0,0" FontWeight="Bold" Foreground="White" Background="#1AFFFFFF" BorderThickness="0" Cursor="Hand"/>
            </WrapPanel>
            <TextBlock Text="任何一项检查不过，都不会启动 Claude" FontSize="10" Foreground="#59FFFFFF" HorizontalAlignment="Center" Margin="0,14,0,0"/>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$win = [Windows.Markup.XamlReader]::Load($reader)

$rows = New-Object System.Collections.ObjectModel.ObservableCollection[Object]
$win.FindName('CheckList').ItemsSource = $rows

$checkNames = @('代理内核','TUN网卡','出口IP','IP一致','时区','地区','IPv6','DNS','WebRTC','保镖','规则置顶','客户端语言','ASN属性','生态可达性')

function Set-Status($text, $color) {
    $win.FindName('StatusText').Text = $text
    $win.FindName('StatusText').Foreground = (New-Object System.Windows.Media.SolidColorBrush $color)
}

function Update-RegionDisplay {
    $file = Join-Path $BASE 'region.json'
    if (-not (Test-Path $file)) { $win.FindName('RegionText').Text = '尚未同步'; return }
    try {
        $r = Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json
        $when = try { ([datetime]$r.updated_at).ToString('yyyy-MM-dd HH:mm') } catch { '时间未知' }
        $win.FindName('RegionText').Text = "$($r.country) / $($r.tz_iana) / $($r.culture) · $when"
    } catch { $win.FindName('RegionText').Text = '地区配置无法读取，请点击同步地区' }
}

$script:activeJob = $null
$script:jobAction = ''
$script:jobTarget = ''
$script:allChecksOk = $false
function Set-ControlsBusy([bool]$busy) {
    $win.FindName('BtnA').IsEnabled = -not $busy -and $script:allChecksOk
    $win.FindName('BtnB').IsEnabled = -not $busy -and $script:allChecksOk
    $win.FindName('BtnRefresh').IsEnabled = -not $busy
    $win.FindName('BtnFix').IsEnabled = -not $busy
    $win.FindName('BtnRegion').IsEnabled = -not $busy
}

function Start-CoreJob([string]$operation, [string]$target = '') {
    if ($script:activeJob) { return }
    $script:jobAction = $operation
    $script:jobTarget = $target
    Set-ControlsBusy $true
    if ($operation -eq 'checkdetail') {
        $rows.Clear()
        foreach ($n in $checkNames) { $rows.Add([pscustomobject]@{ Name = $n; Detail = ''; Icon = '…'; Color = '#FF6B7280' }) }
        Set-Status '检查中' ([System.Windows.Media.Color]::FromRgb(0xFB,0x92,0x3C))
        $win.FindName('Banner').Text = '正在逐项检查环境…'
    } elseif ($operation -eq 'fix') {
        Set-Status '修复中' ([System.Windows.Media.Color]::FromRgb(0xFB,0x92,0x3C))
        $win.FindName('Banner').Text = '正在修复…（必要时会弹出管理员授权框）'
    } elseif ($operation -eq 'set-region') {
        Set-Status '同步地区中' ([System.Windows.Media.Color]::FromRgb(0xFB,0x92,0x3C))
        $win.FindName('Banner').Text = '正在按出口 IP 同步国家、时区和地区格式…'
    } else {
        Set-Status '切换中' ([System.Windows.Media.Color]::FromRgb(0x60,0xA5,0xFA))
        $win.FindName('Banner').Text = "正在切换到账号 $target…（归档可能需要一些时间）"
    }
    $script:activeJob = Start-Job -ArgumentList $CORE,$BASE,$operation,$target -ScriptBlock {
        param($corePath,$basePath,$command,$account)
        $argv = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$corePath,$command)
        if ($account) { $argv += $account }
        if ($command -eq 'checkdetail') {
            $null = & powershell.exe @argv 2>&1
            Get-Content (Join-Path $basePath 'last-check.txt') -Raw -Encoding UTF8
        } else {
            (& powershell.exe @argv 2>&1 | Out-String).Trim()
        }
    }
}

function Finish-Checks([string]$output) {
    $allOk = $true
    $matched = 0
    $failures = @()
    foreach ($line in ($output -split "`r?`n")) {
        $kv = $line -split '=', 2
        if ($kv.Count -ne 2) { continue }
        $index = [array]::IndexOf($checkNames, $kv[0])
        if ($index -lt 0) { continue }
        $matched++
        $st = $kv[1] -split ':', 2
        $detail = if ($st.Count -gt 1) { $st[1] } else { '' }
        if ($st[0] -eq 'fail') {
            $allOk = $false
            $failures += "$($kv[0])：$detail"
            if ($kv[0] -in @('时区','地区')) { $detail += '；建议点击“同步地区”' }
            elseif ($kv[0] -eq '规则置顶') { $detail += '；建议点击“一键修复”' }
        }
        $icon = if ($st[0] -eq 'ok') { '✓' } elseif ($st[0] -eq 'warn') { '⚠' } else { '✗' }
        $color = if ($st[0] -eq 'ok') { '#FF22C55E' } elseif ($st[0] -eq 'warn') { '#FFFACC15' } else { '#FFF87171' }
        $rows[$index] = [pscustomobject]@{ Name = $kv[0]; Detail = $detail; Icon = $icon; Color = $color }
        $win.Dispatcher.Invoke([action]{}, 'Render')
    }
    $script:allChecksOk = ($matched -eq $checkNames.Count -and $allOk)
    if ($script:allChecksOk) {
        Set-Status '环境安全' ([System.Windows.Media.Color]::FromRgb(0x22,0xC5,0x5E))
        $win.FindName('Banner').Text = ''
    } else {
        Set-Status '检查未过' ([System.Windows.Media.Color]::FromRgb(0xF8,0x71,0x71))
        $win.FindName('Banner').Text = if ($failures.Count) { "未通过：$($failures -join '；')" } else { "检测输出不完整($matched/$($checkNames.Count))，请重新检查" }
    }
    $currentFile = Join-Path $BASE 'current.txt'
    $cur = if (Test-Path $currentFile) { Get-Content $currentFile -Raw } else { '' }
    $st = "current=$($cur.Trim())"
    $win.FindName('CurrentAccount').Text = if ($st -match 'current=B') { 'B' } elseif ($st -match 'current=A') { 'A' } else { '未初始化' }
    Update-RegionDisplay
    Set-ControlsBusy $false
}

$poller = New-Object System.Windows.Threading.DispatcherTimer
$poller.Interval = [TimeSpan]::FromMilliseconds(300)
$poller.Add_Tick({
    if (-not $script:activeJob) { return }
    if ($script:activeJob.State -in @('Completed','Failed','Stopped')) {
        $job = $script:activeJob
        $action = $script:jobAction
        $target = $script:jobTarget
        $output = (Receive-Job $job | Out-String).Trim()
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        $script:activeJob = $null
        if ($action -eq 'checkdetail') {
            Finish-Checks $output
        } elseif ($action -eq 'diagnostic') {
            $report = [regex]::Replace($output, '\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\b', '$1.$2.*.*')
            try {
                [Windows.Clipboard]::SetText($report)
                Set-Status '报告已复制' ([System.Windows.Media.Color]::FromRgb(0x22,0xC5,0x5E))
                $win.FindName('Banner').Text = '诊断报告已复制（出口 IP 已脱敏）'
            } catch {
                Set-Status '复制失败' ([System.Windows.Media.Color]::FromRgb(0xF8,0x71,0x71))
                $win.FindName('Banner').Text = '无法访问剪贴板，请重试'
            }
            Set-ControlsBusy $false
        } elseif ($action -eq 'switch') {
            if ($output -match 'FAIL:') {
                Set-Status '检查未过' ([System.Windows.Media.Color]::FromRgb(0xF8,0x71,0x71))
                $win.FindName('Banner').Text = $output
                Set-ControlsBusy $false
            } else {
                $win.FindName('CurrentAccount').Text = $target
                $win.FindName('Banner').Text = "已切换到账号 $target，Claude 启动中。"
                Start-CoreJob 'checkdetail'
            }
        } else {
            if ($output -match 'FAIL:') {
                Set-Status '操作未完成' ([System.Windows.Media.Color]::FromRgb(0xF8,0x71,0x71))
                $win.FindName('Banner').Text = $output
                Set-ControlsBusy $false
            } else {
                Set-Status '操作完成' ([System.Windows.Media.Color]::FromRgb(0x22,0xC5,0x5E))
                $win.FindName('Banner').Text = if ($action -eq 'set-region') { '地区同步完成，正在重新检查…' } else { '修复完成，正在重新检查…' }
                Start-CoreJob 'checkdetail'
            }
        }
    }
})
$poller.Start()

function Copy-DiagnosticReport {
    if ($script:activeJob) { return }
    Set-ControlsBusy $true
    $script:activeJob = Start-Job -ArgumentList $CORE,$BASE -ScriptBlock {
        param($corePath,$basePath)
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $corePath checkdetail 2>$null | Out-Null
        $checks = Get-Content (Join-Path $basePath 'last-check.txt') -Raw -Encoding UTF8
        $region = Get-Content (Join-Path $basePath 'region.json') -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        $meta = try { (& curl.exe -s --max-time 6 'https://ipinfo.io/json' 2>$null | ConvertFrom-Json) } catch { $null }
        "检查结果：`n$checks`n地区配置：`n$region`n出口国家/ASN：$($meta.country) / $($meta.org)"
    }
    $script:jobAction = 'diagnostic'
    Set-Status '生成报告中' ([System.Windows.Media.Color]::FromRgb(0xFB,0x92,0x3C))
}

$win.FindName('BtnRefresh').Add_Click({ Start-CoreJob 'checkdetail' })
$win.FindName('BtnFix').Add_Click({ Start-CoreJob 'fix' })
$win.FindName('BtnRegion').Add_Click({ Start-CoreJob 'set-region' })
$win.FindName('BtnA').Add_Click({ Start-CoreJob 'switch' 'A' })
$win.FindName('BtnB').Add_Click({ Start-CoreJob 'switch' 'B' })
$win.FindName('BtnDiagnostic').Add_Click({
    Copy-DiagnosticReport
})
$win.FindName('BtnLogs').Add_Click({
    Start-Process explorer.exe -ArgumentList "`"$BASE`""
})
$win.Add_ContentRendered({ Update-RegionDisplay; Start-CoreJob 'checkdetail' })
[void]$win.ShowDialog()
