#!/bin/bash
# Claude 保镖 (Linux) —— 代理离线时自动关闭 claude CLI 进程
# 说明: Linux 上 Claude 使用形态是 网页版(浏览器) + Claude Code CLI。
# 保镖只终止 claude CLI(掉了不会误伤你正在用的浏览器)。
# 安装器会把 __PROXY_MODE__ 替换为安装时识别的客户端;未替换(旧装)时按 Clash 内核判定,行为与旧版一致
LOG="$HOME/.claude-switcher/bodyguard.log"
MODE="__PROXY_MODE__"
# 出口 IP 白名单(可选): 文件每行一个允许的出口 IP。存在且非空时,出口不在名单内即断线。
# 日志不记录任何 IP。取不到出口连续 2 次也按失败处理(Fail-Closed)。
ALLOW="$HOME/.claude-switcher/egress-allow"
# 可选: 存在 mihomo-secret 时,通过 mihomo API 检查 claude/anthropic 连接是否走 DIRECT(无需写死节点 IP)
CHAIN="$(dirname "$0")/mihomo-chain-check.py"
SECRET="$HOME/.claude-switcher/mihomo-secret"
tick=0; miss=0; amiss=0

while true; do
    ok=1; reason=""
    # TUN 在线判定:fake-ip 网段优先,通用虚拟网卡(tun/utun/wg/tailscale 且 UP)兜底(WireGuard 无 fake-ip)
    if ! ip addr 2>/dev/null | grep -q 'inet 198\.18\.'; then
        ip link show 2>/dev/null | grep -E '^[0-9]+: (tun|utun|wg|tailscale)[0-9]*:' | grep -q 'UP' || ok=0
    fi
    # 内核在线判定:按安装时识别的客户端分派
    case "$MODE" in
        clash-verge) pgrep -f 'verge-mihomo|mihomo' >/dev/null 2>&1 || ok=0 ;;
        mihomo)      pgrep -f mihomo >/dev/null 2>&1 || ok=0 ;;
        sing-box)    pgrep -f sing-box >/dev/null 2>&1 || ok=0 ;;
        v2raya)      pgrep -f v2raya >/dev/null 2>&1 || ok=0 ;;
        nekobox)     pgrep -f 'nekobox|nekoray' >/dev/null 2>&1 || ok=0 ;;
        hiddify)     pgrep -f hiddify >/dev/null 2>&1 || ok=0 ;;
        wireguard)   systemctl list-units --type=service --state=active 'wg-quick@*' 2>/dev/null | grep -q 'wg-quick@' || ok=0 ;;
        other|auto)  : ;;  # other/auto 只查虚拟网卡(启发式,避免误杀)
        *)           pgrep -f 'verge-mihomo|mihomo' >/dev/null 2>&1 || ok=0 ;;
    esac
    if [ -s "$ALLOW" ] && [ $((tick % 10)) -eq 0 ]; then
        cur=$(curl -s --max-time 3 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | sed -n 's/^ip=//p' | head -1)
        if [ -z "$cur" ]; then
            miss=$((miss + 1))
            [ "$miss" -ge 2 ] && ok=0 && reason="出口探测连续失败"
        else
            miss=0
            tr -d '\r' < "$ALLOW" | grep -qxF "$cur" || { ok=0; reason="出口IP不在白名单"; }
        fi
    fi
    if [ -s "$SECRET" ] && [ -f "$CHAIN" ]; then
        python3 "$CHAIN" >/dev/null 2>&1; rc=$?
        if [ "$rc" -eq 1 ]; then ok=0; reason="claude 连接绕过代理(DIRECT)"; amiss=0
        elif [ "$rc" -eq 2 ]; then amiss=$((amiss + 1)); [ "$amiss" -ge 2 ] && ok=0 && reason="mihomo API 不可用"
        else amiss=0; fi
    fi
    if [ "$ok" -eq 0 ] && pgrep -x claude >/dev/null 2>&1; then
        pkill -x claude
        echo "$(date '+%Y-%m-%d %H:%M:%S') ${reason:-代理离线(内核或TUN丢失)},已自动关闭 claude CLI" >>"$LOG"
    fi
    tick=$((tick + 1))
    sleep 3
done
