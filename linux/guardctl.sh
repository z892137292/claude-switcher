#!/bin/bash
# root 保镖一站式管理(Linux)
# 用法: sudo bash guardctl.sh <命令> [参数]
#   status                     只读体检(服务/配置权限/API/出口白名单/会话数)
#   sync [mihomo配置路径]       从 mihomo 配置同步 API 地址和密钥到 /etc/claude-switcher
#   set-egress                 把当前出口 IP 写入白名单(需确认)
#   install <mode> <用户>       预检通过后安装 root 保镖(依次: sync、预检、安装)
#   harden-controller [配置]    external-controller 改为仅本机监听,并安全重启 mihomo
#   cleanup <用户>              删除该用户目录下的旧配置副本
#   rollback <用户>             回滚到用户态保镖
#   menu                       终端菜单面板(无参数时默认进入)
set -u
umask 022
CONF=/etc/claude-switcher
LIB=/usr/local/lib/claude-switcher
SVC=claude-bodyguard-root
DIR="$(cd "$(dirname "$0")" && pwd)"
MIHOMO_CFG_DEFAULT=/etc/mihomo/config.private.yaml

need_root() { [ "$(id -u)" -eq 0 ] || { echo "X 需要 root: sudo bash $0 $*"; exit 1; }; }
ok()   { echo "  ✓ $*"; }
bad()  { echo "  ✗ $*"; FAIL=1; }
FAIL=0

chain_check() { CLAUDE_SWITCHER_DIR="$CONF" python3 "${1:-$LIB}/mihomo-chain-check.py"; }
egress_ip() { curl -s --max-time 5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | sed -n 's/^ip=//p' | head -1; }

# 从 mihomo 配置读取 API 地址与密钥,只写文件,不打印
cmd_sync() {
    need_root
    local cfg="${1:-$MIHOMO_CFG_DEFAULT}"
    [ -r "$cfg" ] || { echo "X 读不到 $cfg"; exit 1; }
    local ctl secret host port
    ctl=$(sed -n -E 's/^external-controller:[[:space:]]*"?([^"#[:space:]]+).*/\1/p' "$cfg" | head -1)
    secret=$(sed -n -E "s/^secret:[[:space:]]*//p" "$cfg" | head -1 | sed -E "s/[[:space:]]+#.*$//; s/^[\"']//; s/[\"']\$//; s/[[:space:]]+\$//")
    [ -n "$ctl" ] || { echo "X 配置里没有 external-controller"; exit 1; }
    [ -n "$secret" ] || { echo "X 配置里没有 secret(为空密钥不安全,请先设置)"; exit 1; }
    host="${ctl%:*}"; port="${ctl##*:}"
    case "$host" in 0.0.0.0|""|"*"|"::") host=127.0.0.1 ;; esac
    install -d -m 700 -o root -g root "$CONF"
    printf 'http://%s:%s\n' "$host" "$port" > "$CONF/mihomo-api"
    printf '%s\n' "$secret" > "$CONF/mihomo-secret"
    chmod 600 "$CONF/mihomo-api" "$CONF/mihomo-secret"
    echo "✓ 已同步 API 地址与密钥到 $CONF(密钥 $(wc -c < "$CONF/mihomo-secret") 字节,未显示)"
}

cmd_set_egress() {
    need_root
    local ip; ip=$(egress_ip)
    [ -n "$ip" ] || { echo "X 取不到出口 IP"; exit 1; }
    local loc; loc=$(curl -s --max-time 5 https://www.cloudflare.com/cdn-cgi/trace | sed -n 's/^loc=//p')
    echo "当前出口国家: ${loc:-未知}"
    [ "$loc" = "CN" ] && { echo "X 出口是 CN,拒绝写入白名单"; exit 1; }
    read -r -p "确认把当前出口写入白名单(不显示 IP)? [y/N] " a
    [ "$a" = "y" ] || { echo "已取消"; exit 0; }
    install -d -m 700 -o root -g root "$CONF"
    printf '%s\n' "$ip" > "$CONF/egress-allow"; chmod 600 "$CONF/egress-allow"
    echo "✓ 已写入白名单,等待保镖重新检测..."
    wait_guard_ok
}

# 等保镖重新探测并确认恢复正常运行(最多 ~45 秒)
wait_guard_ok() {
    local i st
    [ "$(systemctl is-active $SVC)" = active ] || { echo "  ✗ root 保镖未运行,请先 install"; return 1; }
    for i in $(seq 1 15); do
        sleep 3
        st=$(cat "$CONF/state" 2>/dev/null)
        if [ "$st" = ok ] && [ "$(( $(date +%s) - $(stat -c %Y "$CONF/egress-allow") ))" -ge 4 ]; then
            ok "保镖已重新检测:状态正常,已恢复正常运行(未锁定)"; return 0
        fi
        printf '  . 状态: %s (%ss)\n' "${st:-未知}" $((i * 3))
    done
    bad "超时仍处于锁定/未知状态,查看: sudo tail $CONF/bodyguard.log;若白名单有误请重新运行 set-egress"
    return 1
}

cmd_status() {
    echo "== 服务 =="
    [ "$(systemctl is-active $SVC 2>/dev/null)" = active ] && ok "$SVC active" || bad "$SVC 未运行"
    [ "$(systemctl is-enabled $SVC 2>/dev/null)" = enabled ] && ok "开机自启" || bad "未设置开机自启"
    local n; n=$(pgrep -f "$LIB/claude-bodyguard.sh" | wc -l)
    [ "$n" -eq 1 ] && ok "保镖进程数 1" || bad "保镖进程数 $n(应为 1)"
    echo "== 文件权限 =="
    for f in "$LIB/claude-bodyguard.sh" "$LIB/mihomo-chain-check.py"; do
        [ "$(stat -c '%U %a' "$f" 2>/dev/null)" = "root 755" ] && ok "$f" || bad "$f 属主/权限异常"
    done
    for f in egress-allow mihomo-api mihomo-secret; do
        [ -e "$CONF/$f" ] || { echo "  - $f 未配置"; continue; }
        [ "$(stat -c '%U %a' "$CONF/$f")" = "root 600" ] && ok "$CONF/$f" || bad "$CONF/$f 属主/权限异常"
    done
    echo "== mihomo =="
    pgrep -f mihomo >/dev/null && ok "mihomo 进程在线" || bad "mihomo 进程不在"
    ip addr 2>/dev/null | grep -q '198\.18\.' && ok "TUN(198.18)在线" || bad "TUN 不在线"
    local lis; lis=$(ss -ltn 2>/dev/null | awk '$4 ~ /:9090$/ {print $4}')
    case "$lis" in 127.0.0.1:9090) ok "API 仅本机监听" ;; "") echo "  - 未发现 9090 监听" ;; *) bad "API 监听 $lis(对外开放)" ;; esac
    if [ -s "$CONF/mihomo-secret" ]; then
        chain_check; case $? in 0) ok "API 检查通过" ;; 1) bad "发现 claude 连接走 DIRECT" ;; *) bad "API 不可用" ;; esac
    fi
    echo "== 出口 =="
    local ip loc; ip=$(egress_ip); loc=$(curl -s --max-time 5 https://www.cloudflare.com/cdn-cgi/trace | sed -n 's/^loc=//p')
    [ -n "$ip" ] && echo "  出口国家: ${loc:-未知}" || bad "取不到出口"
    if [ -s "$CONF/egress-allow" ]; then
        tr -d '\r' < "$CONF/egress-allow" | grep -qxF "$ip" && ok "出口在白名单内" || bad "出口不在白名单(30 秒内会终止 claude)"
    else echo "  - 白名单未启用"; fi
    echo "== 会话 =="
    echo "  claude 进程数: $(pgrep -x claude | wc -l)"
    [ -f "$CONF/bodyguard.log" ] && { echo "  最近触发记录:"; tail -3 "$CONF/bodyguard.log" | sed 's/^/    /'; } || echo "  无触发记录"
    echo ""
    if [ "$FAIL" -eq 0 ]; then echo "总体: 正常"; else echo "总体: 有异常(见 ✗)"; return 1; fi
}

cmd_install() {
    need_root
    local mode="${1:?用法: install <mode> <用户>}" user="${2:?缺少用户名}"
    local cfg="${3:-$MIHOMO_CFG_DEFAULT}"
    echo "[1/4] 同步 mihomo API 配置"; cmd_sync "$cfg" || exit 1
    echo "[2/4] 预检 mihomo API(失败则中止,避免装完后误杀会话)"
    chain_check "$DIR"; local rc=$?
    [ "$rc" -eq 0 ] || { echo "X 预检失败(返回 $rc),已中止,未安装"; exit 1; }
    ok "API 预检通过"
    echo "[3/4] 出口白名单"
    if [ -s "$CONF/egress-allow" ]; then
        local ip; ip=$(egress_ip)
        tr -d '\r' < "$CONF/egress-allow" | grep -qxF "$ip" || { echo "X 现有白名单与当前出口不一致,先运行 set-egress 或清空白名单"; exit 1; }
        ok "白名单与当前出口一致"
    else echo "  - 未启用白名单(可稍后运行 set-egress)"; fi
    echo "[4/4] 安装 root 保镖"
    bash "$DIR/install-root-bodyguard.sh" "$mode" "$user" && cmd_status
}

cmd_harden_controller() {
    need_root
    local cfg="${1:-$MIHOMO_CFG_DEFAULT}"
    [ -w "$cfg" ] || { echo "X 配置不可写: $cfg"; exit 1; }
    if grep -qE '^external-controller:[[:space:]]*"?127\.0\.0\.1:' "$cfg"; then
        echo "配置已是仅本机监听"
    else
        cp -p "$cfg" "$cfg.bak-ctrl.$(date +%s)"
        sed -i -E 's|^external-controller:.*|external-controller: 127.0.0.1:9090|' "$cfg"
        echo "✓ 已修改并备份"
    fi
    if ss -ltn | awk '$4 ~ /:9090$/ {print $4}' | grep -qv '^127\.0\.0\.1:9090$'; then
        echo "运行中的 mihomo 仍对外监听,需要重启(会短暂中断代理)"
        read -r -p "现在重启? 将先停保镖,恢复并预检通过后再启动 [y/N] " a
        [ "$a" = "y" ] || { echo "已跳过重启(未生效)"; exit 0; }
        systemctl stop $SVC 2>/dev/null
        systemctl restart mihomo; sleep 4
        ip addr | grep -q '198\.18\.' || { echo "X mihomo0 未恢复,保镖保持停止,请排查: journalctl -u mihomo -n 20"; exit 1; }
        cmd_sync "$cfg" >/dev/null
        local rc=2 i
        for i in 1 2 3 4 5; do chain_check; rc=$?; [ "$rc" -ne 2 ] && break; sleep 2; done
        [ "$rc" -eq 0 ] || { echo "X API 预检失败($rc),保镖保持停止"; exit 1; }
        systemctl start $SVC && echo "✓ 已重启 mihomo 并恢复保镖"
    fi
}

cmd_cleanup() {
    need_root
    local user="${1:?用法: cleanup <用户>}" home
    home=$(getent passwd "$user" | cut -d: -f6); [ -n "$home" ] || { echo "X 用户不存在"; exit 1; }
    [ "$(systemctl is-active $SVC)" = active ] || { echo "X root 保镖未运行,拒绝清理旧副本"; exit 1; }
    rm -f "$home/.claude-switcher/mihomo-secret" "$home/.claude-switcher/egress-allow" "$home/.claude-switcher/mihomo-api"
    echo "✓ 已删除 $user 目录下的旧配置副本"
}

cmd_rollback() { need_root; bash "$DIR/install-root-bodyguard.sh" --rollback "${1:?用法: rollback <用户>}"; }

# 子命令含 exit,放进子 shell 执行,避免退出整个菜单
cmd_menu() {
    need_root
    local def_user="${SUDO_USER:-claude}" n u m
    while true; do
        echo; echo "===== Claude 保镖面板 ====="
        echo " 1) 状态体检        2) 同步 mihomo API 配置"
        echo " 3) 更新出口白名单  4) 安装/更新 root 保镖"
        echo " 5) API 改仅本机监听 6) 清理旧配置副本"
        echo " 7) 回滚用户态保镖  8) 查看保镖日志"
        echo " 9) 环境预检(checkdetail)   0) 退出"
        read -r -p "选择: " n
        case "$n" in
            1) (cmd_status) ;;
            2) read -r -p "mihomo 配置路径 [$MIHOMO_CFG_DEFAULT]: " u; (cmd_sync "${u:-$MIHOMO_CFG_DEFAULT}") ;;
            3) (cmd_set_egress) ;;
            4) read -r -p "代理模式 [mihomo]: " m; read -r -p "运行用户 [$def_user]: " u
               (cmd_install "${m:-mihomo}" "${u:-$def_user}") ;;
            5) (cmd_harden_controller) ;;
            6) read -r -p "用户 [$def_user]: " u; (cmd_cleanup "${u:-$def_user}") ;;
            7) read -r -p "用户 [$def_user]: " u; (cmd_rollback "${u:-$def_user}") ;;
            8) tail -n 20 "$CONF/bodyguard.log" 2>/dev/null || echo "  无触发记录" ;;
            9) bash "$DIR/claude-switch.sh" checkdetail ;;
            0|q|"") return 0 ;;
            *) echo "无效选择" ;;
        esac
    done
}

c="${1:-}"; shift || true
[ -z "$c" ] && [ -t 0 ] && c=menu
case "$c" in
    menu) cmd_menu ;;
    status) cmd_status ;;
    sync) cmd_sync "$@" ;;
    set-egress) cmd_set_egress ;;
    install) cmd_install "$@" ;;
    harden-controller) cmd_harden_controller "$@" ;;
    cleanup) cmd_cleanup "$@" ;;
    rollback) cmd_rollback "$@" ;;
    *) sed -n 2,12p "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
