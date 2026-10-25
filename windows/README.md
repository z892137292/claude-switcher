# Claude 切换器 · Windows（Claude Code 默认模式，Beta）

本版默认在新 PowerShell 终端中运行 **Claude Code CLI**，无需安装 Claude 桌面客户端。A/B 使用官方支持的 `CLAUDE_CONFIG_DIR` 配置目录，不搬移登录凭据，不复制桌面账号快照。

## 安装和使用

1. 先在普通 PowerShell 中确认 `claude --version` 能运行。支持原生安装的 `claude.exe` 和 npm 的 `claude.cmd` / `claude.ps1`。如果刚安装 Code，请退出并重开切换器，让 PATH 更新。
2. 开启代理客户端的 TUN 模式，下载本开发分支的完整 ZIP 并解压。不要只替换一个脚本。
3. 用管理员 PowerShell 执行 `windows\install.ps1`（也可运行 `windows\install.bat`）。安装器更新脚本和守护任务，切换到 Code 模式，保留原出口基准及账号配置。
4. 打开桌面「Claude切换器」，等待安全检查，点「选择项目」并选择要开发的文件夹。
5. 点「Code A · 原有配置」：在所选项目目录打开 `claude`，使用 `%USERPROFILE%\.claude`，保留该目录已有登录。
6. 点「Code B · 独立配置」：使用 `%USERPROFILE%\.claude-switcher\code-profiles\B`。首次按 Claude Code 提示登录，以后继续使用该配置。

A/B 可以各开一个终端；点击另一个配置不会强制关闭正在工作的 Code。界面只报告终端启动结果，不认定登录成功或订阅可用，具体状态以 Code 终端为准。终端退出后按回车关闭窗口。

如果平时设置了自定义 `CLAUDE_CONFIG_DIR`，本版 A 仍明确使用默认的 `%USERPROFILE%\.claude`，不会自动导入那个自定义目录。也不会导入 VS Code 扩展的独立登录或接管已经打开的 IDE 会话。

## 出口和保护边界

`region.json` 记录固定 IP、国家、时区和地区格式。缺失、损坏、IP/国家不匹配或探测失败会阻止启动；Code 真正运行前会再次核验出口、TUN 和保镖状态。

保镖通过启动记录里的 PID 和进程开始时间识别本工具的终端，并在网络检查失败时请求关闭该终端及其子进程，包括 npm 模式的 cmd/node 子进程。**不会按名字关闭全部 node.exe，也不会接管你另外打开的 Claude Code 或 VS Code 扩展。** 如关闭进程失败，日志会注明未完成并在下一轮重试。

每轮检查后等待 10 秒，另加最长约 8 秒出口请求和调度时间。这是进程巡检，存在检测窗口，不能替代防火墙断网规则，探测请求自身也可能经过变化后的网络。TUN 网卡存在不等于全部流量已接管；规则是静态检查；STUN 无响应只显示未确认警告。

所有 14 个检查项必须唯一且完整；失败、缺项、重复和未知状态阻止启动，警告/信息项供参考。HTTP 探测不代表账号已登录。

地区看门狗只恢复保存的时区和格式，不自动接受新出口。确需更换出口时：退出本工具的 Code 会话，在界面点「重新锁定出口」并确认。安装升级不会覆盖已有基准；旧基准缺少 `exit_ip` 时，先从新版目录运行 `claude-switch.ps1 set-region` 明确重锁，再安装。

## 认证说明

配置隔离采用 [Claude Code 官方多账号方式](https://code.claude.com/docs/en/authentication#log-in-with-multiple-accounts)。首次登录交给官方 CLI；本工具不读取或记录密码、Cookie、API Key、OAuth Token。

继承的 `ANTHROPIC_API_KEY`、`ANTHROPIC_AUTH_TOKEN`、`CLAUDE_CODE_OAUTH_TOKEN` 或云供应商变量可能优先于目录里的登录。终端只提示变量名，不输出值，不擅自删除或更改变量。共用同一 API Key 时，A/B 不代表不同计费账号；项目/组织配置也仍可能影响认证。官方说明中，不使用 API Key 的两组 Claude Console 登录不能仅靠配置目录隔离。

## 文件和兼容

- `launch.json`：模式和项目路径；默认 `code`。CLI 可运行 `claude-switch.ps1 set-project "D:\项目目录"` 保存项目。
- `code-current.txt`：最近启动的 Code 配置；与旧桌面模式的 `current.txt` 分开。
- `code-runs/`：终端进程身份及启动状态，不含凭据。
- `code-profiles/B/`：B 的私有配置，包含 Code 自己保存的登录资料，请勿提交到 Git 或上传诊断。
- 原有 `accounts/` 桌面快照保持原样，不作为 Code 凭据使用。核心仍保留 `set-mode desktop` 供旧桌面模式使用，但新版 UI 面向 Code。
- Windows PowerShell 5.1+；脚本保持 UTF-8 BOM，后台操作通过 UTF-8 文件返回结果，避免中文错误被控制台代码页破坏。
- 卸载默认保留 `accounts/` 和 `code-profiles/`，A 的原有 `.claude` 目录不属于卸载范围。

## 验证

在仓库根目录运行：

```powershell
powershell -NoProfile -File tests/windows-safety.ps1
powershell -NoProfile -File tests/windows-code.ps1
```

GitHub Actions 分别用 Windows PowerShell 5.1 和 PowerShell 7 跑隔离测试。Code 测试使用临时目录和假 CLI，验证 A/B 配置、项目路径、中文结果、进程树与 PID 复用保护，不接触真实账号或代理。真实 Code 登录、代理中断和 WPF 仍需真机验收。

## UDP/STUN 诊断

WebRTC 行实际运行独立的 IPv4 UDP STUN 探针，不是浏览器 ICE 测试，也不能覆盖所有 IPv6 或浏览器特有行为。

每个服务器设置 DNS 等待 1.5 秒、网络阶段共 4 秒；同一套接字/事务最多发送两次。四个服务器顺序执行，全部超时可能约 22 秒，另加调度/处理时间。报文校验包含 Binding 响应类型、magic cookie、事务 ID、消息长度和属性边界，支持 MAPPED/XOR-MAPPED 地址解析。仅所有服务器返回有效且一致的出口时显示绿色；部分失败保持黄色，发现不同出口时显示红色并要求核实路由，不直接断言一定是本地真实 IP 泄漏。

点击「复制诊断报告」会附上 STUN 明细；或「打开日志」查看 `stun-diagnostics.txt`。文件含生成时间、公开服务器名称、状态、发送/接收字节、尝试次数、无效报文数和耗时；映射 IP 脱敏，不记录原始报文或凭据。

- `timeout`：发送后截止期限内没有收到数据报。
- `invalid_response`：收到了数据，但报文无效或事务不匹配；具体原因在 detail。
- `dns_error` / `dns_timeout` / `dns_no_ipv4`：发送前的名称解析阶段失败。
- `send_error` / `receive_error`：套接字收发错误，detail 给出错误类别。
- `stun_error`：服务端返回 STUN 错误码。

测试：`powershell -NoProfile -File tests/windows-stun.ps1`。使用合成报文和本机 UDP 回环，不连接公共 STUN 或修改代理。不要为了测试变绿而改为直连或关闭防火墙。
