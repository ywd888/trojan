#!/bin/bash

# ====================================================
# Project: Sing-box Trojan One-Click
# Author: ywd888
# Repo: https://github.com/ywd888/trojan
# ====================================================

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

CONFIG="/etc/sing-box/config.json"

# 1. 基础环境检查
check_env() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 权限运行!${PLAIN}" && exit 1
    
    # 自动安装基础组件
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${YELLOW}正在安装 curl...${PLAIN}"
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y curl
        elif command -v yum >/dev/null 2>&1; then
            yum install -y curl
        fi
    fi

    if ! command -v openssl >/dev/null 2>&1 || ! command -v ss >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            apt-get install -y openssl iproute2
        elif command -v yum >/dev/null 2>&1; then
            yum install -y openssl iproute2
        fi
    fi
}

# 2. 安装 Sing-box 核心
install_core() {
    if ! command -v sing-box >/dev/null 2>&1; then
        echo -e "${BLUE}正在安装 Sing-box 核心...${PLAIN}"
        bash <(curl -fsSL https://sing-box.app/install.sh)
        systemctl enable sing-box
    fi
}

# 3. 获取公网 IP
get_ip() {
    local ip=$(curl -s4m 5 ipv4.icanhazip.com || curl -s4m 5 ifconfig.me)
    [[ -z "$ip" ]] && ip=$(curl -s6m 5 ipv6.icanhazip.com || curl -s6m 5 ifconfig.me)
    echo "$ip"
}

# 4. 生成节点逻辑
gen_node() {
    install_core
    
    # 端口查重
    while :; do
        PORT=$(shuf -i 20000-60000 -n 1)
        [[ $(ss -tuln | grep -w "$PORT") ]] || break
    done

    PASS=$(openssl rand -base64 12 | tr -d /=+ | cut -c1-16)
    
    echo -e "${BLUE}--- 配置信息 ---${PLAIN}"
    read -p "请输入伪装域名 (SNI, 默认 apps.apple.com): " SNI
    SNI=${SNI:-apps.apple.com}

    IP=$(get_ip)
    mkdir -p /etc/sing-box

    # 生成自签名证书
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/sing-box/key.pem -out /etc/sing-box/cert.pem \
        -subj "/CN=$SNI" >/dev/null 2>&1

    # 写入 JSON
    cat > $CONFIG <<EOF
{
  "log": {"level": "info"},
  "inbounds": [
    {
      "type": "trojan",
      "listen": "::",
      "listen_port": $PORT,
      "users": [{"password": "$PASS"}],
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "certificate_path": "/etc/sing-box/cert.pem",
        "key_path": "/etc/sing-box/key.pem"
      }
    }
  ],
  "outbounds": [{"type": "direct"}]
}
EOF

    systemctl restart sing-box
    
    # 防火墙放行
    if command -v ufw >/dev/null 2>&1; then
        ufw allow $PORT/tcp && ufw allow $PORT/udp
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=$PORT/tcp
        firewall-cmd --permanent --add-port=$PORT/udp
        firewall-cmd --reload
    fi

    # 适配 IPv6 链接格式
    HOST=$IP
    [[ $IP == *":"* ]] && HOST="[$IP]"
    
    LINK="trojan://$PASS@$HOST:$PORT?security=tls&sni=$SNI&allowInsecure=1#Trojan-$IP"

    echo -e "\n${GREEN}✅ 节点部署完成!${PLAIN}"
    echo -e "${BLUE}端口:${PLAIN} $PORT"
    echo -e "${BLUE}密码:${PLAIN} $PASS"
    echo -e "${BLUE}SNI:${PLAIN}  $SNI"
    echo -e "${GREEN}链接:${PLAIN} $LINK"
}

# 5. 主菜单
menu() {
    clear
    echo -
