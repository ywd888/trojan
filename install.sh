#!/bin/bash

# ====================================================
# Project: Sing-box Trojan One-Click
# Author: ywd888
# ====================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

CONFIG="/etc/sing-box/config.json"

check_env() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 权限运行!${PLAIN}" && exit 1
    if ! command -v curl >/dev/null 2>&1; then
        apt-get update && apt-get install -y curl || yum install -y curl
    fi
    if ! command -v jq >/dev/null 2>&1; then
        apt-get install -y jq || yum install -y jq
    fi
}

get_ip() {
    local ip=$(curl -s4m 5 ipv4.icanhazip.com || curl -s4m 5 ifconfig.me)
    echo "$ip"
}

gen_node() {
    if ! command -v sing-box >/dev/null 2>&1; then
        echo -e "${BLUE}正在安装 Sing-box...${PLAIN}"
        bash <(curl -fsSL https://sing-box.app/install.sh)
        systemctl enable sing-box
    fi

    # 随机端口
    while :; do
        PORT=$(shuf -i 20000-60000 -n 1)
        [[ $(ss -tuln | grep -w "$PORT") ]] || break
    done

    # 随机密码
    PASS=$(openssl rand -base64 12 | tr -d /=+ | cut -c1-16)

    # SNI 输入
    read -p "请输入 SNI (默认 apps.apple.com): " SNI
    SNI=${SNI:-apps.apple.com}

    IP=$(get_ip)

    mkdir -p /etc/sing-box
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/sing-box/key.pem -out /etc/sing-box/cert.pem \
        -subj "/CN=$SNI" >/dev/null 2>&1

    # 写配置文件
    cat > $CONFIG <<EOF
{
  "log": {"level": "info"},
  "inbounds": [{
    "type": "trojan",
    "listen": "0.0.0.0",
    "listen_port": $PORT,
    "users": [{"password": "$PASS"}],
    "tls": {
      "enabled": true,
      "server_name": "$SNI",
      "certificate_path": "/etc/sing-box/cert.pem",
      "key_path": "/etc/sing-box/key.pem"
    }
  }],
  "outbounds": [{"type": "direct"}]
}
EOF

    systemctl restart sing-box

    # 防火墙 TCP+UDP
    if command -v ufw >/dev/null 2>&1; then
        ufw allow $PORT/tcp >/dev/null 2>&1
        ufw allow $PORT/udp >/dev/null 2>&1
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=$PORT/tcp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=$PORT/udp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi

    LINK="trojan://$PASS@$IP:$PORT?security=tls&sni=$SNI&allowInsecure=1#Trojan-$IP"

    echo -e "\n${GREEN}✅ 节点部署成功!${PLAIN}"
    echo -e "${BLUE}节点链接:${PLAIN} $LINK"
}

delete_node() {
    systemctl stop sing-box >/dev/null 2>&1
    rm -rf /etc/sing-box
    echo -e "${RED}节点已删除${PLAIN}"
}

fix_password() {
    # 自动检测 config.json 是否密码写死为 "password"
    if [ -f "$CONFIG" ]; then
        PW_CURRENT=$(jq -r '.inbounds[0].users[0].password' $CONFIG)
        if [ "$PW_CURRENT" = "password" ] || [ -z "$PW_CURRENT" ]; then
            NEWPASS=$(openssl rand -base64 12 | tr -d /=+ | cut -c1-16)
            jq ".inbounds[0].users[0].password=\"$NEWPASS\"" $CONFIG > /tmp/config.json && mv /tmp/config.json $CONFIG
            systemctl restart sing-box
            echo -e "${GREEN}已自动修复密码为: $NEWPASS${PLAIN}"
        fi
    fi
}

show_link() {
    fix_password
    if [ -f "$CONFIG" ]; then
        P=$(jq '.inbounds[0].listen_port' $CONFIG)
        PW=$(jq -r '.inbounds[0].users[0].password' $CONFIG)
        S=$(jq -r '.inbounds[0].tls.server_name' $CONFIG)
        I=$(get_ip)
        echo -e "${GREEN}trojan://$PW@$I:$P?security=tls&sni=$S&allowInsecure=1#Trojan-$I${PLAIN}"
    else
        echo -e "${RED}未安装节点${PLAIN}"
    fi
}

menu() {
    echo -e "${YELLOW}====== Sing-box Trojan 管理 ======${PLAIN}"
    echo -e "1. 新建/重置节点"
    echo -e "2. 删除节点"
    echo -e "3. 查看节点链接"
    echo -e "0. 退出"
    echo -e "${YELLOW}================================${PLAIN}"
}

main() {
    check_env
    while true; do
        clear
        menu
        read -p "请选择: " choice
        case "$choice" in
            1) gen_node ;;
            2) delete_node ;;
            3) show_link ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选项${PLAIN}" ;;
        esac
        read -p "按回车继续..."
    done
}

main
