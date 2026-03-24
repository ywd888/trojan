#!/bin/bash

# ================== 配置 ==================
DOWNLOAD_INSTALL_SH="https://raw.githubusercontent.com/bqlpfy/ssr/refs/heads/master/install.sh"
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

get_ip() {
    curl -s4m 5 ipv4.icanhazip.com || curl -s6m 5 ipv6.icanhazip.com
}

check_udp() {
    PORT="$1"
    # 检查 UDP 端口是否被监听
    if ss -u -lnt | grep -q ":$PORT"; then
        echo "UDP: 已开启"
    else
        echo "UDP: 未开启"
    fi
}

# ================== 核心操作 ==================
new_node() {
    echo -e "${BLUE}== 新建/重置节点 ==${PLAIN}"

    # 下载官方安装脚本
    echo -e "${BLUE}正在调用官方 install.sh 安装 SSServer...${PLAIN}"
    curl -L "$DOWNLOAD_INSTALL_SH" -o ./install.sh
    chmod +x ./install.sh
    ./install.sh

    # 检查服务状态
    sleep 1
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}节点已部署成功!${PLAIN}"
        show_link
    else
        echo -e "${RED}节点启动失败，请检查日志: sudo journalctl -u $SERVICE_NAME -f${PLAIN}"
    fi
}

show_link() {
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        IP=$(get_ip)
        PORT=$(grep -oP '(?<=-s \[::\]:)\d+' <<< "$(systemctl cat $SERVICE_NAME | grep ExecStart)")
        PASSWORD=$(grep -oP '(?<=-k )[^ ]+' <<< "$(systemctl cat $SERVICE_NAME | grep ExecStart)")
        UDP_STATUS=$(check_udp "$PORT")
        LINK="ss://$(echo -n "chacha20-ietf-poly1305:$PASSWORD" | base64 -w0)@$IP:$PORT?#Node-$IP"
        echo -e "${GREEN}当前节点链接: ${PLAIN}$LINK"
        echo -e "${YELLOW}端口状态: ${PLAIN}TCP 已开启, $UDP_STATUS"
    else
        echo -e "${RED}节点未运行或未创建${PLAIN}"
    fi
}

delete_node() {
    echo -e "${RED}== 删除节点 ==${PLAIN}"
    systemctl stop "$SERVICE_NAME" >/dev/null 2>&1
    systemctl disable "$SERVICE_NAME" >/dev/null 2>&1
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    rm -f /usr/local/bin/ssserver
    systemctl daemon-reload
    echo -e "${RED}节点已删除${PLAIN}"
}

# ================== 菜单 ==================
main_menu() {
    check_root
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
            0) echo -e "${BLUE}退出菜单，返回 shell${PLAIN}" ; break ;;
            *) echo -e "${RED}无效选项${PLAIN}" ;;
        esac
    done
}

# ================== 入口 ==================
main_menu
