#!/bin/bash

CONFIG="/etc/sing-box/config.json"

gen_node() {
  PORT=$(shuf -i 20000-60000 -n 1)
  PASS=$(openssl rand -base64 12 | tr -d /=+ | cut -c1-16)
  read -p "请输入 SNI（默认 apps.apple.com）: " SNI
  SNI=${SNI:-apps.apple.com}

  IP=$(curl -s ipv4.icanhazip.com || curl -s ifconfig.me)

  mkdir -p /etc/sing-box

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

  openssl req -x509 -nodes -days 3650 \
  -newkey rsa:2048 \
  -keyout /etc/sing-box/key.pem \
  -out /etc/sing-box/cert.pem \
  -subj "/CN=$SNI" >/dev/null 2>&1

  systemctl enable sing-box >/dev/null 2>&1
  systemctl restart sing-box

  ufw allow $PORT/tcp >/dev/null 2>&1
  ufw allow $PORT/udp >/dev/null 2>&1

  # IPv6兼容
  if [[ $IP == *":"* ]]; then
    HOST="[$IP]"
  else
    HOST="$IP"
  fi

  LINK="trojan://$PASS@$HOST:$PORT?security=tls&sni=$SNI&allowInsecure=1#Trojan-$IP"

  echo ""
  echo "✅ 创建成功"
  echo "端口: $PORT"
  echo "密码: $PASS"
  echo "SNI: $SNI"
  echo ""
  echo "节点链接："
  echo "$LINK"
}

delete_node() {
  systemctl stop sing-box 2>/dev/null
  rm -rf /etc/sing-box
  echo "❌ 节点已删除"
}

change_sni() {
  if [ ! -f "$CONFIG" ]; then
    echo "❌ 未安装节点"
    return
  fi

  read -p "输入新的 SNI: " NEWSNI

  sed -i "s/server_name.*/server_name\": \"$NEWSNI\",/" $CONFIG

  openssl req -x509 -nodes -days 3650 \
  -newkey rsa:2048 \
  -keyout /etc/sing-box/key.pem \
  -out /etc/sing-box/cert.pem \
  -subj "/CN=$NEWSNI" >/dev/null 2>&1

  systemctl restart sing-box
  echo "✅ SNI 已修改为: $NEWSNI"
}

show_node() {
  if [ ! -f "$CONFIG" ]; then
    echo "❌ 未安装节点"
    return
  fi

  PORT=$(grep listen_port $CONFIG | awk '{print $2}' | tr -d ',')
  PASS=$(grep password $CONFIG | awk -F '"' '{print $4}')
  SNI=$(grep server_name $CONFIG | awk -F '"' '{print $4}')
  IP=$(curl -s ipv4.icanhazip.com || curl -s ifconfig.me)

  if [[ $IP == *":"* ]]; then
    HOST="[$IP]"
  else
    HOST="$IP"
  fi

  LINK="trojan://$PASS@$HOST:$PORT?security=tls&sni=$SNI&allowInsecure=1#Trojan-$IP"

  echo "当前节点："
  echo "$LINK"
}

install_core() {
  if ! command -v sing-box >/dev/null 2>&1; then
    bash <(curl -fsSL https://sing-box.app/install.sh)
  fi
}

menu() {
  clear
  echo "====== Trojan 管理 ======"
  echo "1. 新建节点"
  echo "2. 删除节点"
  echo "3. 修改 SNI"
  echo "4. 查看节点"
  echo "0. 退出"
  echo "========================="
}

install_core

while true; do
  menu
  read -p "请选择: " choice
  case $choice in
    1) gen_node ;;
    2) delete_node ;;
    3) change_sni ;;
    4) show_node ;;
    0) exit 0 ;;
    *) echo "无效选项" ;;
  esac
  read -p "按回车继续..."
done
