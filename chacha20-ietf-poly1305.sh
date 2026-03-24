#!/bin/bash

# ================== 配置 ==================
DOWNLOAD_URL="https://raw.githubusercontent.com/ywd888/dailijiaoben"
DEFAULT_PASSWORD="Fas+fsYq/Pdy881lVTakDw"
DEFAULT_PORT="15370"
BINARY_NAME="ssserver"
INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="ssserver"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# ================== 工具函数 ==================
check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 权限运行!${PLAIN}" && exit 1
}

enable_tfo() {
    current_tfo=$(cat /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null || echo "0")
    if [[ $current_tfo -lt 3 ]]; then
        echo 3 > /proc/sys/net/ipv4/tcp_fastopen
        if ! grep -q "net.ipv4.tcp_fastopen" /etc/sysctl.conf; then
            echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
        else
            sed -i 's/^net.ipv4.tcp_fastopen.*/net.ipv4.tcp_fastopen = 3/' /etc/sysctl.conf
        fi
    fi
}

get_ip() {
    curl -s4m 5 ipv4.icanhazip.com || curl -s6m 5 ipv6.icanhazip.com
}

# ================== 核心操作 ==================
new_node() {
    echo -e "${BLUE}== 新建/重置节点 ==${PLAIN}"
    
    # 下载 ssserver
    if [ ! -f "$INSTALL_DIR/$BINARY_NAME" ]; then
        echo "下载 ssserver..."
        curl -L -o "$BINARY_NAME" "$DOWNLOAD_URL"
        chmod +x "$BINARY_NAME"
        cp "$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
    fi

    # 获取密码和端口
    read -p "请输入密码 (默认: $DEFAULT_PASSWORD): " PASSWORD
    PASSWORD=${PASSWORD:-$DEFAULT_PASSWORD}
    read -p "请输入端口 (默认: $DEFAULT_PORT): " PORT
    PORT=${PORT:-$DEFAULT_PORT}

    # 创建 systemd 服务
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
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
    systemctl restart "$SERVICE_NAME"

    echo -e "${GREEN}节点已部署成功!${PLAIN}"
    show_link
}

show_link() {
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        PORT=$(grep -oP '(?<=-s \[::\]:)\d+' <<< "$(cat /etc/systemd/system/$SERVICE_NAME.service)")
        PASSWORD=$(grep -oP '(?<=-k )[^ ]+' <<< "$(cat /etc/systemd/system/$SERVICE_NAME.service)")
        IP=$(get_ip)
        LINK="ss://$(echo -n "chacha20-ietf-poly1305:$PASSWORD" | base64 -w0)@$IP:$PORT?#Node-$IP"
        echo -e "${GREEN}当前节点链接: ${PLAIN}$LINK"
    else
        echo -e "${RED}节点未运行或未创建${PLAIN}"
    fi
}

delete_node() {
    echo -e "${RED}== 删除节点 ==${PLAIN}"
    systemctl stop "$SERVICE_NAME" >/dev/null 2>&1
    systemctl disable "$SERVICE_NAME" >/dev/null 2>&1
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    rm -f "$INSTALL_DIR/$BINARY_NAME"
    systemctl daemon-reload
    echo -e "${RED}节点已删除${PLAIN}"
}

# ================== 菜单 ==================
main_menu() {
    check_root
    enable_tfo
    while true; do
        echo -e "\n${YELLOW}=== SSServer 节点管理 ===${PLAIN}"
        echo -e "  1. 新建/重置节点"
        echo -e "  2. 查看当前节点链接"
        echo -e "  3. 删除节点"
        echo -e "  0. 退出"
        read -p "请选择: " choice
        case "$choice" in
            1) new_node ;;
            2) show_link ;;
            3) delete_node ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选项${PLAIN}" ;;
        esac
    done
}

# ================== 入口 ==================
main_menu
