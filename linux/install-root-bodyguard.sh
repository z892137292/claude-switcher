#!/bin/bash
# 把保镖升级为 root 持有的 systemd 系统服务(claude 用户无法停止或改写)
# 用法: sudo bash install-root-bodyguard.sh <proxy-mode> <claude-user>
#   例: sudo bash install-root-bodyguard.sh mihomo claude
# 回滚: sudo bash install-root-bodyguard.sh --rollback <claude-user>
set -e
umask 022
[ "$(id -u)" -eq 0 ] || { echo "X 需要 root(sudo)"; exit 1; }

LIB=/usr/local/lib/claude-switcher
CONF=/etc/claude-switcher
UNIT=/etc/systemd/system/claude-bodyguard-root.service
DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$1" = "--rollback" ]; then
    U="${2:?用法: --rollback <claude-user>}"
    systemctl disable --now claude-bodyguard-root.service 2>/dev/null || true
    rm -f "$UNIT"; systemctl daemon-reload
    systemctl --machine="$U"@.host --user enable --now claude-bodyguard.service 2>/dev/null \
        || echo "请以 $U 身份执行: systemctl --user enable --now claude-bodyguard"
    echo "✓ 已回滚(配置保留在 $CONF,可手动删除)"; exit 0
fi

MODE="${1:?用法: install-root-bodyguard.sh <proxy-mode> <claude-user>}"
U="${2:?缺少 claude 用户名}"
case "$MODE" in clash-verge|mihomo|sing-box|v2raya|nekobox|hiddify|wireguard|other|auto) ;; *) echo "X 未知 proxy-mode: $MODE"; exit 1 ;; esac
id "$U" >/dev/null 2>&1 || { echo "X 用户不存在: $U"; exit 1; }
UH=$(getent passwd "$U" | cut -d: -f6)

# 脚本放 root 目录,配置放 /etc,均 root 所有,claude 用户不可写
install -d -m 755 -o root -g root "$LIB"
install -d -m 700 -o root -g root "$CONF"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
sed "s|__PROXY_MODE__|$MODE|g" "$DIR/claude-bodyguard.sh" > "$TMP"
bash -n "$TMP"
install -m 755 -o root -g root "$TMP" "$LIB/claude-bodyguard.sh"
install -m 755 -o root -g root "$DIR/mihomo-chain-check.py" "$LIB/mihomo-chain-check.py"
bash -n "$LIB/claude-bodyguard.sh"

# 迁移现有配置(不覆盖已存在的)
for f in egress-allow mihomo-api mihomo-secret; do
    if [ -s "$UH/.claude-switcher/$f" ] && [ ! -e "$CONF/$f" ]; then
        install -m 600 -o root -g root "$UH/.claude-switcher/$f" "$CONF/$f"
    fi
done

cat > "$UNIT" <<EOF
[Unit]
Description=Claude Bodyguard (root; kill claude CLI when proxy down)
After=network-online.target

[Service]
Environment=CLAUDE_SWITCHER_DIR=$CONF
ExecStart=/bin/bash $LIB/claude-bodyguard.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "$UNIT"

# 先停用户态保镖,避免两个实例并存
systemctl --machine="$U"@.host --user disable --now claude-bodyguard.service 2>/dev/null \
    || echo "! 请以 $U 身份执行: systemctl --user disable --now claude-bodyguard"

systemctl daemon-reload
systemctl enable --now claude-bodyguard-root.service
sleep 1
systemctl is-active claude-bodyguard-root.service
echo "✓ root 保镖已启动。验证: systemctl status claude-bodyguard-root; 日志: $CONF/bodyguard.log"
