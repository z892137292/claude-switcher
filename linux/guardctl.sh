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
#   set-yaml <新配置> [目标配置]  更换节点配置:校验、备份、重启 mihomo、同步 API、更新白名单、确认恢复,失败自动回滚
#   diagnose [秒数]            抓取 claude/anthropic 走 DIRECT 的连接(域名/规则,不含 IP),默认 120 秒
#   egress-mode follow|static  出口校验模式: follow=只验证当前节点出口(节点切换自动重学);static=固定白名单
#   menu                       终端菜单面板(无参数时默认进入)
set -u
umask 022
CONF=/etc/claude-switcher
LIB=/usr/local/lib/claude-switcher
SVC=claude-bodyguard-root
DIR="$(cd "$(dirname "$0")" && pwd)"
MIHOMO_CFG_DEFAULT=/etc/mihomo/config.private.yaml
NFT_FILE="${NFT_FILE:-/etc/mihomo/kill-switch.nft}"
NFT_SVC="${NFT_SVC:-vm104-guard}"

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
    elif [ -f "$CONF/egress-follow" ]; then ok "出口校验: 跟随当前节点(保镖状态: $(cat "$CONF/state" 2>/dev/null || echo 未知))"
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

nft_public_ips() {
    grep -E 'ip daddr [0-9]' "$1" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$1" | grep -vE '^(10\.|127\.|0\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|198\.1[89]\.|169\.254\.)' | sort -u
}

# 从 yaml 取全部节点 server 并解析为 IPv4(域名用 getent)
yaml_node_ips() {
    grep -E '^[[:space:]-]*server:|[{,][[:space:]]*server:' "$1" | sed -E 's/.*server:[[:space:]]*"?'"'"'?([^"'"'"',}[:space:]]+).*/\1/' | sort -u | while read -r h; do
        [ -n "$h" ] || continue
        if echo "$h" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then echo "$h"
        else getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}' | sort -u; fi
    done | sort -u
}

# 把防火墙里的节点 IP 同步为新 yaml 的节点 IP;旧文件备份到 $1(备份路径)
sync_nft() {
    local yaml="$1" bak="$2" new_ips old_ips tmp
    [ -f "$NFT_FILE" ] || { echo "  - 无 $NFT_FILE,跳过防火墙同步"; return 0; }
    new_ips=$(yaml_node_ips "$yaml")
    [ -n "$new_ips" ] || { echo "X 新配置解析不出节点 IP(域名解析失败?),为避免断网中止"; return 1; }
    old_ips=$(nft_public_ips "$NFT_FILE")
    if [ "$old_ips" = "$new_ips" ]; then ok "防火墙节点 IP 已是最新"; return 0; fi
    [ -n "$old_ips" ] || { echo "X 防火墙文件里找不到可替换的节点 IP,请手动处理"; return 1; }
    tmp=$(mktemp)
    # 取含公网 IP 的第一行为模板,每个新 IP 生成一行;其余含旧 IP 的行删除
    python3 - "$NFT_FILE" "$tmp" "$old_ips" "$new_ips" <<'PY' || { rm -f "$tmp"; return 1; }
import re,sys
src,dst,old,new=sys.argv[1],sys.argv[2],sys.argv[3].split(),sys.argv[4].split()
lines=open(src,encoding="utf-8").read().split("\n")
pat=re.compile("|".join(re.escape(o) for o in old))
rule=re.compile(r"ip daddr ")
out=[];tpl=None;done=False
for l in lines:
    if rule.search(l) and pat.search(l):
        if tpl is None: tpl=l
        if not done:
            m=pat.search(l)
            for ip in new: out.append(pat.sub(ip,tpl))
            done=True
        continue
    out.append(l)
open(dst,"w",encoding="utf-8").write("\n".join(out))
PY
    nft -c -f "$tmp" 2>/dev/null || { rm -f "$tmp"; echo "X 生成的防火墙文件校验失败,未改动"; return 1; }
    cp -p "$NFT_FILE" "$bak"
    cat "$tmp" > "$NFT_FILE"; rm -f "$tmp"
    systemctl restart "$NFT_SVC" || { cat "$bak" > "$NFT_FILE"; systemctl restart "$NFT_SVC"; echo "X 重载防火墙失败,已还原"; return 1; }
    ok "防火墙已放行新节点 IP($(echo "$new_ips" | wc -l) 个),旧节点 IP 已移除"
    check_nft_set "$new_ips"
}

# 防火墙若用命名集合(@mihomo_nodes)放行节点,提示其中是否已含新节点 IP(集合的维护方式因部署而异,不擅自改)
check_nft_set() {
    grep -q '@mihomo_nodes' "$NFT_FILE" 2>/dev/null || return 0
    local setout ip miss=0
    setout=$(nft list set inet vm104_guard mihomo_nodes 2>/dev/null) || { echo "  - 无法读取集合 mihomo_nodes,请确认其包含新节点 IP"; return 0; }
    echo "$setout" | grep -q 'elements' || return 0   # 空集合=未使用,无需处理
    for ip in $1; do echo "$setout" | grep -qF "$ip" || miss=1; done
    [ "$miss" -eq 0 ] && ok "集合 mihomo_nodes 已含新节点 IP" || echo "  ! 集合 mihomo_nodes 未包含全部新节点 IP,请检查其维护方式(若无其它脚本维护,需手动加入)"
}

# 更换节点配置(mihomo yaml)。全程先停保镖;任何一步失败都回滚旧配置并恢复保镖
cmd_set_yaml() {
    need_root
    local new="${1:?用法: set-yaml <新yaml路径> [目标配置]}" cfg="${2:-$MIHOMO_CFG_DEFAULT}"
    [ -r "$new" ] || { echo "X 读不到 $new"; exit 1; }
    [ -f "$cfg" ] || { echo "X 目标配置不存在: $cfg"; exit 1; }
    local bak="$cfg.bak-yaml.$(date +%s)" tmp
    tmp=$(mktemp "$cfg.new.XXXXXX") || exit 1
    cp "$new" "$tmp"
    # 新配置缺 API 设置时沿用旧配置的值;controller 一律收紧为仅本机
    if ! grep -qE '^secret:[[:space:]]*[^[:space:]#]' "$tmp"; then
        local old_secret; old_secret=$(grep -E '^secret:' "$cfg" | head -1)
        [ -n "$old_secret" ] || { rm -f "$tmp"; echo "X 新旧配置都没有 secret"; exit 1; }
        sed -i -E '/^secret:/d' "$tmp"; printf '%s\n' "$old_secret" >> "$tmp"
    fi
    sed -i -E '/^external-controller:/d' "$tmp"
    printf 'external-controller: 127.0.0.1:9090\n' >> "$tmp"
    if command -v mihomo >/dev/null 2>&1; then
        mihomo -d "$(dirname "$cfg")" -t -f "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; echo "X mihomo 校验新配置失败,未改动"; exit 1; }
        ok "mihomo 校验通过"
    else echo "  - 未找到 mihomo 命令,跳过语法校验"; fi
    echo "将替换 $cfg(备份 $bak),期间保镖暂停、代理短暂中断。"
    read -r -p "继续? [y/N] " a
    [ "$a" = "y" ] || { rm -f "$tmp"; echo "已取消"; exit 0; }
    systemctl stop $SVC 2>/dev/null
    cp -p "$cfg" "$bak"
    cat "$tmp" > "$cfg"; rm -f "$tmp"
    local nftbak="$bak.nft"
    rollback_yaml() {
        echo "X $1,回滚旧配置"
        [ -f "$nftbak" ] && { cat "$nftbak" > "$NFT_FILE"; systemctl restart "$NFT_SVC"; }
        cat "$bak" > "$cfg"; systemctl restart mihomo; sleep 4
        cmd_sync "$cfg" >/dev/null 2>&1
        systemctl start $SVC; exit 1
    }
    sync_nft "$cfg" "$nftbak" || rollback_yaml "防火墙同步失败"
    systemctl restart mihomo; sleep 4
    ip addr | grep -q '198\.18\.' || rollback_yaml "mihomo0 未恢复"
    cmd_sync "$cfg" >/dev/null || rollback_yaml "同步 API 失败"
    local rc=2 i
    for i in 1 2 3 4 5; do chain_check; rc=$?; [ "$rc" -ne 2 ] && break; sleep 2; done
    [ "$rc" -eq 0 ] || rollback_yaml "API 预检失败($rc)"
    local loc ip
    loc=$(curl -s --max-time 8 https://www.cloudflare.com/cdn-cgi/trace | sed -n 's/^loc=//p')
    ip=$(egress_ip)
    { [ -n "$ip" ] && [ -n "$loc" ] && [ "$loc" != CN ]; } || rollback_yaml "新节点出口异常(国家: ${loc:-未知})"
    ok "新节点出口国家: $loc"
    if [ -s "$CONF/egress-allow" ]; then
        printf '%s\n' "$ip" > "$CONF/egress-allow"; chmod 600 "$CONF/egress-allow"
        ok "白名单已更新为新出口"
    fi
    systemctl start $SVC
    if [ -s "$CONF/egress-allow" ]; then wait_guard_ok || exit 1
    else sleep 6; [ "$(cat "$CONF/state" 2>/dev/null)" = ok ] && ok "保镖状态正常" || bad "保镖状态异常,查看 $CONF/bodyguard.log"; fi
}

# 抓取 claude/anthropic 域名走 DIRECT 的连接,汇总显示命中的域名与规则(不输出 IP)
cmd_diagnose() {
    need_root
    local secs="${1:-120}" api sec out i
    api=$(cat "$CONF/mihomo-api" 2>/dev/null); sec=$(cat "$CONF/mihomo-secret" 2>/dev/null)
    [ -n "$api" ] || { echo "X 缺少 $CONF/mihomo-api,先运行 sync"; exit 1; }
    out=$(mktemp)
    echo "抓取 ${secs} 秒,请在此期间正常使用 claude..."
    for i in $(seq 1 $((secs / 2))); do
        curl -s --max-time 3 -H "Authorization: Bearer $sec" "$api/connections" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for c in d.get("connections") or []:
    m=c.get("metadata") or {}; h=(m.get("host") or "").lower()
    if ("claude" in h or "anthropic" in h) and "DIRECT" in (c.get("chains") or []):
        print(h, "|规则:", c.get("rule"), c.get("rulePayload"), "|进程:", m.get("process") or "-")
' >> "$out"
        sleep 2
    done
    if [ -s "$out" ]; then echo "命中 DIRECT 的连接(次数 域名 规则 进程):"; sort "$out" | uniq -c | sort -rn
    else echo "✓ 期间没有 claude/anthropic 连接走 DIRECT"; fi
    rm -f "$out"
}

cmd_egress_mode() {
    need_root
    case "${1:-}" in
        follow)
            [ -s "$CONF/mihomo-secret" ] || { echo "X follow 依赖 mihomo API,先运行 sync"; exit 1; }
            local n; n=$(CLAUDE_SWITCHER_DIR="$CONF" python3 "$LIB/mihomo-chain-check.py" --node)
            [ -n "$n" ] || { echo "X 取不到当前节点(策略组默认 GLOBAL,可设置环境变量 MIHOMO_GROUP)"; exit 1; }
            ok "当前节点已识别"
            [ -s "$CONF/egress-allow" ] && mv -f "$CONF/egress-allow" "$CONF/egress-allow.disabled"
            : > "$CONF/egress-follow"; chmod 600 "$CONF/egress-follow"
            echo "✓ 已启用跟随模式:只验证当前节点出口,切换节点自动重学。保镖需重启以载入新逻辑:"
            echo "  sudo bash $0 install mihomo <用户>"
            ;;
        static)
            rm -f "$CONF/egress-follow"
            [ -f "$CONF/egress-allow.disabled" ] && mv -f "$CONF/egress-allow.disabled" "$CONF/egress-allow" && ok "已恢复固定白名单"
            echo "✓ 已切回固定白名单模式(如无白名单,运行 set-egress)"
            ;;
        *) echo "用法: egress-mode follow|static"; exit 1 ;;
    esac
}

# 子命令含 exit,放进子 shell 执行,避免退出整个菜单
cmd_menu() {
    need_root
    local n
    while true; do
        echo
        echo "===== Claude 保镖：日常使用 ====="
        echo " 1) 检查环境和保护状态"
        echo " 2) 查看最近的保护记录"
        echo " 0) 退出"
        echo "节点切换请继续使用 Mihomo 面板；本菜单不修改节点配置。"
        read -r -p "选择: " n
        case "$n" in
            1) bash "$DIR/claude-switch.sh" checkdetail ;;
            2)
                if [ -s "$CONF/bodyguard.log" ]; then
                    tail -n 12 "$CONF/bodyguard.log"
                else
                    echo "暂无保护触发记录。"
                fi
                ;;
            0|q|"") return 0 ;;
            *) echo "请输入 1、2 或 0。" ;;
        esac
    done
}

c="${1:-}"; shift || true
[ -z "$c" ] && [ -t 0 ] && c=menu
case "$c" in
    menu) cmd_menu ;;
    egress-mode) cmd_egress_mode "$@" ;;
    diagnose) cmd_diagnose "$@" ;;
    set-yaml) cmd_set_yaml "$@" ;;
    status) cmd_status ;;
    sync) cmd_sync "$@" ;;
    set-egress) cmd_set_egress ;;
    install) cmd_install "$@" ;;
    harden-controller) cmd_harden_controller "$@" ;;
    cleanup) cmd_cleanup "$@" ;;
    rollback) cmd_rollback "$@" ;;
    *) sed -n 2,12p "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
