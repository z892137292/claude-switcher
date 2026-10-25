# Claude 账号切换器 - Windows 界面 (WPF, Beta)
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$BASE = "$env:USERPROFILE\.claude-switcher"
$CORE = "$BASE\claude-switch.ps1"
. (Join-Path $BASE 'region-functions.ps1')
. (Join-Path $BASE 'code-functions.ps1')

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Code 环境启动器" Width="540" Height="980" ResizeMode="CanResize"
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
                <TextBlock Text="Claude Code 环境启动器" FontSize="18" FontWeight="Bold"/>
                <TextBlock Text="安全检查 · 独立配置 · 终端启动" FontSize="11" Foreground="#8AFFFFFF"/>
            </StackPanel>
            <Border x:Name="StatusPill" Margin="60,0,0,0" Padding="12,5" CornerRadius="12" Background="#2E22C55E" VerticalAlignment="Center">
                <TextBlock x:Name="StatusText" Text="检查中" FontSize="11" FontWeight="Bold" Foreground="#FFFB923C"/>
            </Border>
        </StackPanel>

        <Border Grid.Row="1" CornerRadius="12" Background="#0DFFFFFF" BorderBrush="#14FFFFFF" BorderThickness="1" Padding="10" Margin="0,0,0,10">
            <StackPanel>
                <TextBlock Text="出口IP锁定地区" FontSize="11" Foreground="#80FFFFFF"/>
                <TextBlock x:Name="RegionText" Text="尚未同步" FontSize="13" FontWeight="Bold" Margin="0,4,0,0"/>
                <TextBlock x:Name="ProjectText" Text="项目目录：未选择" FontSize="11" Margin="0,6,0,0" TextWrapping="Wrap"/>
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
                <TextBlock Text="最近启动配置" FontSize="11" Foreground="#80FFFFFF" VerticalAlignment="Center"/>
                <Border Margin="6,0,0,0" Padding="10,3" CornerRadius="10" Background="#4D6366F1">
                    <TextBlock x:Name="CurrentAccount" Text="?" FontSize="11" FontWeight="Bold" Foreground="#FFA5B4FC"/>
                </Border>
            </StackPanel>
            <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="10"/><ColumnDefinition/></Grid.ColumnDefinitions>
                <Button x:Name="BtnA" Grid.Column="0" Content="Code A · 原有配置" Height="52" FontSize="15" FontWeight="Bold"
                        Foreground="White" Background="#7A6366F1" BorderThickness="0" Cursor="Hand"/>
                <Button x:Name="BtnB" Grid.Column="2" Content="Code B · 独立配置" Height="52" FontSize="15" FontWeight="Bold"
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
                <Button x:Name="BtnRegion" Content="重新锁定出口" Padding="12,8" Margin="8,0,0,0" FontWeight="Bold" Foreground="White" Background="#1AFFFFFF" BorderThickness="0" Cursor="Hand"/>
                <Button x:Name="BtnDiagnostic" Content="复制诊断报告" Padding="12,8" Margin="8,0,0,0" FontWeight="Bold" Foreground="White" Background="#1AFFFFFF" BorderThickness="0" Cursor="Hand"/>
                <Button x:Name="BtnProject" Content="选择项目" Padding="12,8" Margin="8,0,0,0" Foreground="White" Background="#1AFFFFFF" BorderThickness="0" Cursor="Hand"/>
                <Button x:Name="BtnLogs" Content="打开日志" Padding="12,8" Margin="8,0,0,0" FontWeight="Bold" Foreground="White" Background="#1AFFFFFF" BorderThickness="0" Cursor="Hand"/>
            </WrapPanel>
            <TextBlock Text="必需检查未通过时阻止启动；警告和信息项供参考" FontSize="10" Foreground="#59FFFFFF" HorizontalAlignment="Center" Margin="0,14,0,0"/>
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
        $when = try { ([datetime]$r.locked_at).ToString('yyyy-MM-dd HH:mm') } catch { '时间未知' }
        $win.FindName('RegionText').Text = "$($r.country) / $($r.tz_iana) / $($r.culture) · $when"
    } catch { $win.FindName('RegionText').Text = '地区配置无法读取，请点击重新锁定出口' }
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
    $win.FindName('BtnProject').IsEnabled = -not $busy
}

function Start-CoreJob([string]$operation, [string]$target = '') {
    if ($script:activeJob) { return }
    $script:jobAction = $operation
    $script:jobTarget = $target
    Set-ControlsBusy $true
    if ($operation -eq 'checkdetail') {
        $script:allChecksOk = $false
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
        $win.FindName('Banner').Text = "正在打开 Claude Code 配置 $target…"
    }
    $script:activeJob = Start-Job -ArgumentList $CORE,$BASE,$operation,$target -ScriptBlock {
        param($corePath,$basePath,$command,$account)
        . (Join-Path (Split-Path $corePath -Parent) 'code-functions.ps1')
        Invoke-CoreUtf8 $corePath $basePath $command $account

    }
}

function Finish-Checks([string]$output) {
    $report = Test-CheckReport ($output -split "`r?`n")
    $allOk = $report.passed
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
            if ($kv[0] -in @('时区','地区')) { $detail += '；建议点击“一键修复”' }
            elseif ($kv[0] -eq '规则置顶') { $detail += '；建议点击“一键修复”' }
        }
        $icon = if ($st[0] -eq 'ok') { '✓' } elseif ($st[0] -eq 'warn') { '⚠' } elseif ($st[0] -eq 'info') { 'ℹ' } else { '✗' }
        $color = if ($st[0] -eq 'ok') { '#FF22C55E' } elseif ($st[0] -eq 'warn') { '#FFFACC15' } elseif ($st[0] -eq 'info') { '#FF60A5FA' } else { '#FFF87171' }
        $rows[$index] = [pscustomobject]@{ Name = $kv[0]; Detail = $detail; Icon = $icon; Color = $color }
        $win.Dispatcher.Invoke([action]{}, 'Render')
    }
    $script:allChecksOk = ($matched -eq $checkNames.Count -and $allOk)
    if ($script:allChecksOk) {
        if ($output -match '(?m)^[^=]+=warn:') {
            Set-Status '有未确认项' ([System.Windows.Media.Color]::FromRgb(0xFB,0x92,0x3C))
            $win.FindName('Banner').Text = '部分检查尚未确认，请查看黄色条目；当前策略允许启动。'
        } else {
            Set-Status '启动条件通过' ([System.Windows.Media.Color]::FromRgb(0x22,0xC5,0x5E))
            $win.FindName('Banner').Text = '结果仅代表本次检查；蓝色条目为信息，不代表已验证。'
        }
    } else {
        Set-Status '检查未过' ([System.Windows.Media.Color]::FromRgb(0xF8,0x71,0x71))
        $win.FindName('Banner').Text = if ($failures.Count) { "未通过：$($failures -join '；')" } else { "检测输出不完整($matched/$($checkNames.Count))，请重新检查" }
    }
    $currentFile = if ((Get-LaunchMode) -eq 'code') { Join-Path $BASE 'code-current.txt' } else { Join-Path $BASE 'current.txt' }
    $cur = if (Test-Path $currentFile) { Get-Content $currentFile -Raw } else { '' }
    $st = "current=$($cur.Trim())"
    $win.FindName('CurrentAccount').Text = if ($st -match 'current=B') { 'B' } elseif ($st -match 'current=A') { 'A' } else { '未初始化' }
    Update-RegionDisplay
    $win.FindName('ProjectText').Text = '项目目录：' + (Get-LaunchSettings).workspace
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
        $jobSucceeded = $job.State -eq 'Completed'
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
            if (-not $jobSucceeded -or $output -notmatch '(?m)^(OK:|INFO:当前已是账号)' -or $output -match 'FAIL:') {
                Set-Status '检查未过' ([System.Windows.Media.Color]::FromRgb(0xF8,0x71,0x71))
                $win.FindName('Banner').Text = $output
                Set-ControlsBusy $false
            } else {
                $win.FindName('CurrentAccount').Text = $target
                $win.FindName('Banner').Text = "Claude Code 配置 $target 的终端已打开，请在终端查看登录结果。"
                Start-CoreJob 'checkdetail'
            }
        } else {
            if (-not $jobSucceeded -or -not $output -or ($action -eq 'set-region' -and $output -notmatch '(?m)^OK:') -or $output -match 'FAIL:') {
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
        . (Join-Path (Split-Path $corePath -Parent) 'code-functions.ps1')
        $checks = Invoke-CoreUtf8 $corePath $basePath 'checkdetail'

        $r = Get-Content (Join-Path $basePath 'region.json') -Raw -Encoding UTF8 -ErrorAction SilentlyContinue | ConvertFrom-Json
        $region = $r | Select-Object country,tz_iana,tz_windows,culture,locked_at | ConvertTo-Json
        $meta = try { (& curl.exe -s --max-time 6 'https://ipinfo.io/json' 2>$null | ConvertFrom-Json) } catch { $null }
        $stun=Get-Content (Join-Path $basePath 'stun-diagnostics.txt') -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        "检查结果：`n$checks`n地区配置：`n$region`n出口国家/ASN：$($meta.country) / $($meta.org)`nSTUN诊断：`n$stun"
    }
    $script:jobAction = 'diagnostic'
    Set-Status '生成报告中' ([System.Windows.Media.Color]::FromRgb(0xFB,0x92,0x3C))
}

$win.FindName('BtnRefresh').Add_Click({ Start-CoreJob 'checkdetail' })
$win.FindName('BtnFix').Add_Click({ Start-CoreJob 'fix' })
$win.FindName('BtnRegion').Add_Click({
    $answer = [System.Windows.MessageBox]::Show('请先退出 Claude 并确认当前代理出口正确。是否将当前 IP、国家和地区设置保存为新基准？', '重新锁定出口', 'YesNo', 'Warning')
    if ($answer -eq 'Yes') { Start-CoreJob 'set-region' }
})
$win.FindName('BtnA').Add_Click({ Start-CoreJob 'switch' 'A' })
$win.FindName('BtnB').Add_Click({ Start-CoreJob 'switch' 'B' })
$win.FindName('BtnDiagnostic').Add_Click({
    Copy-DiagnosticReport
})
$win.FindName('BtnProject').Add_Click({
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = '选择 Claude Code 要工作的项目文件夹'
    $dialog.SelectedPath = (Get-LaunchSettings).workspace
    try {
        if ($dialog.ShowDialog() -eq 'OK') {
            Set-CodeWorkspace $dialog.SelectedPath
            $win.FindName('ProjectText').Text = '项目目录：' + $dialog.SelectedPath
        }
    } catch { $win.FindName('Banner').Text = $_.Exception.Message }
    finally { $dialog.Dispose() }
})
$win.FindName('BtnLogs').Add_Click({
    Start-Process explorer.exe -ArgumentList "`"$BASE`""
})
$win.Add_ContentRendered({ Update-RegionDisplay; $win.FindName('ProjectText').Text = '项目目录：' + (Get-LaunchSettings).workspace; Start-CoreJob 'checkdetail' })
[void]$win.ShowDialog()
