# Claude 切换器 · Windows 版 (Beta)

> ⚠️ **本版本为 Beta,未经大规模真机测试**。核心逻辑移植自 macOS 稳定版,但 Windows 环境差异大,遇到问题请到 [Issues](https://github.com/YOURSJEYO/claude-switcher/issues) 反馈。

## 系统要求

- Windows 10 / 11 (64 位)
- PowerShell 5.1+（Windows 自带,无需安装）
- 代理客户端（需支持 TUN 模式），安装器会自动探测并写入 `$PROXY_MODE`:
  - **Clash Verge** —— 存在配置目录即识别，可自动写入置顶规则
  - **sing-box / ClashX / Surge / WireGuard** —— 按进程或服务识别
  - **其他 TUN 客户端**（Astrill / OpenVPN / Tailscale 等）—— 安装时选 `other`
  - **auto** —— 任一已知进程/服务命中即视为在线（未识别到客户端时的默认选项）
- Claude 桌面版 Windows
- 安装时需要**管理员权限**（注册守护任务 / 设置时区和地区 / 关闭 IPv6）

> 代理模式同时写入 `%USERPROFILE%\.claude-switcher\proxy-mode.txt`，保镖按这个文件分派检测逻辑；缺失时按旧版 Clash Verge 行为处理。

## 安装

1. 先开启代理（TUN 模式）。安装器按出口 IP 自动识别国家、IANA 时区和地区格式，写入 `%USERPROFILE%\.claude-switcher\region.json`。出口为 `CN` 时会拒绝同步；只有确需跳过 CN 限制时才设置 `$env:FORCE=1`
2. 右键 `install.ps1` →「使用 PowerShell 运行」,或在管理员 PowerShell 中执行
3. 如果提示禁止运行脚本,先执行一次:
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   ```
4. 按提示确认/选择代理客户端，走完流程后桌面会出现「Claude切换器」快捷方式
5. 安装器会注册登录启动及每 5 分钟运行的地区看门狗，并在结束时列出完整检查结果

换节点后可以在界面点「同步地区」，或运行：
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude-switcher\claude-switch.ps1" set-region
```
目标国家、时区和 culture 保存在 `region.json`，不再靠改写核心脚本。看门狗检测到出口国家变化时会要求连续两次探测一致后再切换；时区/地区设置漂移会自动恢复，日志位于 `%USERPROFILE%\.claude-switcher\region-watchdog.log`。设置系统时区/位置时如非管理员会弹出一次 UAC；未知的 IANA 时区会明确警告并保留现有时区，不会静默套用美东时区。

## 多代理客户端支持

| 客户端 | `$PROXY_MODE` | 存活判定 | 说明 |
|---|---|---|---|
| Clash Verge | `clash-verge` | `verge-mihomo` 进程 + TUN | 支持自动写入置顶规则 |
| sing-box | `sing-box` | `sing-box` 进程 + TUN | 置顶规则需自行配置 |
| ClashX | `clashx` | `ClashX` 进程 + TUN | 置顶规则需自行配置 |
| Surge | `surge` | `Surge` 进程 + TUN | 置顶规则需自行配置 |
| WireGuard | `wireguard` | `WireGuardTunnel*` 服务 + TUN | 置顶规则需自行配置 |
| 其他 TUN 客户端 | `other` | 仅 TUN | 不要求特定进程，避免误杀 |
| 自动 | `auto` | 任一已知进程/服务 + TUN | 保镖在 `auto` 下同样只查 TUN |

TUN 判定顺序：先看是否存在 `198.18.x.x` 假 IP（Clash 系 fake-ip）；没有则回退到任意处于 `Up` 状态、描述匹配 `TAP/TUN/WireGuard/Wintun/VPN/Tailscale` 的虚拟网卡。198.18 命中时保持原来的 `TUN网卡=ok`；回退命中时显示 `TUN网卡=ok:通用虚拟网卡`。

## 与 macOS 版的差异（注意事项）

> Windows 版地区目标按出口 IP 自动配置，支持 `set-region` 和地区看门狗；时区映射表覆盖多个主流国家/城市。未覆盖的 IANA 时区会警告并保留当前系统时区。Shadowrocket 仅 macOS 可用；自动更新与 48 小时 IP 审查目前仅 macOS 版提供。

| 项目 | 说明 |
|---|---|
| 地区同步 | `region.json` 记录国家、Windows/IANA 时区、culture 与最近更新时间；出口国家切换需连续两次探测一致 |
| 时区名称 | Windows 使用 `Eastern Standard Time` 等 Windows ID；未识别映射时不会回退到美东时区 |
| 地区看门狗 | `ClaudeRegionWatchdog` 登录启动并每 5 分钟运行，隐藏窗口、最高权限；日志为 `region-watchdog.log` |
| 保镖频率 | 计划任务登录启动,隐藏窗口常驻,每 10 秒巡检(与 Mac 一致) |
| 保镖判定 | 显式客户端模式按「客户端进程/服务 + TUN」；`auto` / `other` 只查 TUN |
| IPv6 | 关闭的是物理网卡的 ms_tcpip6 绑定；恢复命令见卸载提示 |
| SmartScreen | 首次运行可能弹"Windows 已保护你的电脑" → 点「更多信息」→「仍要运行」 |
| 账号数据目录 | Windows 版在 `%APPDATA%\Claude`(与 macOS 路径不同,逻辑相同) |
| 卸载 | 运行 `uninstall.bat`，或管理员 PowerShell 执行 `uninstall.ps1`；默认保留 accounts 账号存档 |

## 已知限制

- 设备指纹体检（`fingerprint`）与 Web 检测页为 macOS/浏览器能力，Windows 版暂未内置，可用 Web 版检查 Canvas/WebGL。
- 界面是 WPF 重写的第一版,样式以 Mac 版为准对齐,细节可能有出入
- Clash Verge 的 TUN 开关在 Windows 上如果被更新重置,目前需要手动在设置里重新打开(一键修复会提示)
- 账号快照切换前请确保 Claude 已完全退出(托盘图标也要退出)
- 任意安全检查 `fail` 都会阻止启动 Claude；切换归档使用 robocopy 退出码 0–7 成功并做 `.new` / `.previous` 原子替换。遇到待恢复快照时先确认数据，不要直接删除。
- 界面检查/修复在后台执行；「复制诊断报告」会对 IPv4 脱敏，「打开日志」打开配置目录。保镖关闭 Claude 时会尝试显示 Windows 托盘通知，通知失败会记入 `bodyguard.log`。
- **`auto` / `other` 的 TUN 判定是通用启发式**:只要有一块处于 `Up` 状态、描述里带 `TAP/TUN/WireGuard/Wintun/VPN/Tailscale` 的网卡就会判定 TUN 在线,无法区分"代理隧道已接管"还是"某块虚拟网卡只是存在"。可能误判(例如虚拟网卡残留、其他 VPN 适配器),此时请把 `$PROXY_MODE` 改成实际客户端后重跑安装器;若仍不稳定,可在计划任务中暂停 `ClaudeBodyguard`
- **非 Clash 客户端**:保镖已按客户端模式分派,不再因缺少 `verge-mihomo` 每 10 秒误杀 Claude;`规则置顶` 检查只读 Clash Verge 的 `profiles\Merge.yaml` 与 `clash-verge.yaml`，非 Clash 用户需自行配置 Claude 域名及 STUN 端口规则。`DNS` 检查也按 `198.18.x.x` 判断,使用非 fake-ip TUN 时可能显示 `fail`,不代表代理不可用
- Windows 版仍为 Beta，未覆盖的 IANA 时区将保留现有时区；`Set-WinSystemLocale` 的系统级设置可能需注销或重启后完全生效。
- 系统区域为 zh-CN(控制台代码页 936/GBK)时,界面通过读取核心脚本落盘的 `last-check.txt`(UTF-8)展示检查结果,不受代码页影响;若你看到"检测输出不完整(3/14)"且用的是旧版界面,请更新到最新版
