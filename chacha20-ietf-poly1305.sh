#!/bin/bash

BINARY_NAME="ssserver"
INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="ssserver"
DEFAULT_PASSWORD="Fas+fsYq/Pdy881lVTakDw"
DEFAULT_PORT="15370"
DOWNLOAD_URL="https://raw.githubusercontent.com/ywd888/dailijiaoben"

CONFIG_FILE="/etc/ssserver_node.conf"

check_root() {
    [[ $EUID -ne 0 ]] && echo "请使用 root 权限运行！" && exit 1
}

install_ssserver() {
    if ! command -v $BINARY_NAME >/dev/null 2>&1; then
        echo "下载并安装 ssserver..."
        curl -L -o "$BINARY_NAME" "$DOWNLOAD_URL"
        chmod +x "$BINARY_NAME"
        cp "$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
    fi
}

create_node() {
    read -p "请输入节点密码 (默认: $DEFAULT_PASSWORD): " PASSWORD
    PASSWORD=${PASSWORD:-$DEFAULT_PASSWORD}
    read -p "请输入节点端口 (默认: $DEFAULT_PORT): " PORT
    PORT=${PORT:-$DEFAULT_PORT}

    echo "$PASSWORD:$PORT" > "$CONFIG_FILE"

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
    echo "节点已创建并启动！"
}

show_node() {
    if [ -f "$CONFIG_FILE" ]; then
        IFS=":" read -r PASSWORD PORT < "$CONFIG_FILE"
        IP=$(curl -s4m 5 ipv4.icanhazip.com || curl -s6m 5 ipv6.icanhazip.com)
        HOST=$IP
        [[ $IP == *":"* ]] && HOST="[$IP]"
        LINK="ss://chacha20-ietf-poly1305:$PASSWORD@$HOST:$PORT"
        echo "=== 节点链接 ==="
        echo "$LINK"
    else
        echo "没有节点，请先创建节点！"
    fi
}

delete_node() {
    systemctl stop "$SERVICE_NAME" >/dev/null 2>&1
    rm -f "$CONFIG_FILE"
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload
    echo "节点已删除！"
}

menu() {
    while true; do
        echo ""
        echo "=== SSServer 节点管理 ==="
        echo "1. 新建/重置节点"
        echo "2. 查看节点链接"
        echo "3. 删除节点"
        echo "0. 退出"
        read -p "请选择: " choice
        case "$choice" in
            1) create_node ;;
            2) show_node ;;
            3) delete_node ;;
            0) exit 0 ;;
            *) echo "无效选项" ;;
        esac
    done
}

main() {
    check_root
    install_ssserver
    menu
}

main
