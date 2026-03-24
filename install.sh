#!/bin/bash

# =========================
# SSServer 一键安装 + 节点管理
# Author: ywd888
# Repo: https://github.com/ywd888/trojan
# =========================

DOWNLOAD_URL="https://raw.githubusercontent.com/ywd888/dailijiaoben"
DEFAULT_PASSWORD="Z6dcK1YS0BXW"
DEFAULT_PORT="15370"
BINARY_NAME="ssserver"
INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="ssserver"
CONFIG_FILE="/etc/ssserver_node.info"

echo "=== SSServer 安装脚本 ==="
echo "下载地址: $DOWNLOAD_URL"
echo ""

# 检查 root 权限
[[ $EUID -ne 0 ]] && echo "错误: 请使用 root 权限运行" && exit 1

# TCP Fast Open 设置
current_tfo=$(cat /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null || echo "0")
[[ $current_tfo -lt 3 ]] && echo 3 > /proc/sys/net/ipv4/tcp_fastopen && \
    grep -q "net.ipv4.tcp_fastopen" /etc/sysctl.conf || echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf

# 用户输入密码/端口
read -p "请输入密码 (默认 $DEFAULT_PASSWORD): " PASSWORD
PASSWORD=${PASSWORD:-$DEFAULT_PASSWORD}

read -p "请输入端口 (默认 $DEFAULT_PORT): " PORT
PORT=${PORT:-$DEFAULT_PORT}

echo -e "\n配置信息: 密码=$PASSWORD 端口=$PORT"

# 下载 ssserver
curl -L -o "$BINARY_NAME" "$DOWNLOAD_URL" || { echo "下载失败"; exit 1; }
chmod +x "$BINARY_NAME"
cp "$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"

# 创建 systemd 服务
cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=SSServer Service
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=$INSTALL_DIR/$BINARY_NAME -s [::]:$PORT -k $PASSWORD -m chacha20-ietf-poly1305 -U --tcp-fast-open
Restart=always
RestartSec=3
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

# 保存节点信息
echo "$PASSWORD:$PORT" > "$CONFIG_FILE"

echo -e "\n✅ 安装完成！"
echo "服务名称: $SERVICE_NAME"
echo "监听地址: 0.0.0.0:$PORT"
echo "密码: $PASSWORD"
echo "加密方式: chacha20-ietf-poly1305"
echo "TCP Fast Open: 已开启"

# ===== 节点管理功能 ===== #
gen_node() {
    PASSWORD=$(openssl rand -base64 12 | tr -d /=+ | cut -c1-16)
    PORT=$(shuf -i 20000-60000 -n 1)
    echo "$PASSWORD:$PORT" > "$CONFIG_FILE"
    sed -i "s#ExecStart=.*#ExecStart=$INSTALL_DIR/$BINARY_NAME -s [::]:$PORT -k $PASSWORD -m chacha20-ietf-poly1305 -U --tcp-fast-open#" /etc/systemd/system/$SERVICE_NAME.service
    systemctl daemon-reload
    systemctl restart "$SERVICE_NAME"
    echo -e "\n✅ 节点已新建/重置\n密码: $PASSWORD\n端口: $PORT"
}

show_link() {
    if [ -f "$CONFIG_FILE" ]; then
        PW=$(cut -d: -f1 "$CONFIG_FILE")
        P=$(cut -d: -f2 "$CONFIG_FILE")
        IP=$(curl -s4m 5 ipv4.icanhazip.com || curl -s4m 5 ifconfig.me)
        echo -e "\n🔗 节点链接:"
        echo "trojan://$PW@$IP:$P?security=tls&sni=apps.apple.com&allowInsecure=1#SSR-$IP"
    else
        echo -e "\n⚠️ 节点未创建"
    fi
}

# 菜单管理
while :; do
    echo -e "\n=== 节点管理 ==="
    echo "1. 新建/重置节点"
    echo "2. 查看节点链接"
    echo "0. 退出"
    read -p "请选择: " choice
    case "$choice" in
        1) gen_node ;;
        2) show_link ;;
        0) break ;;
        *) echo "无效选项" ;;
    esac
done
