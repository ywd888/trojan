#!/bin/bash

set -e

echo "==== Trojan 一键安装（sing-box）===="

# 随机端口 & 密码
PORT=$(shuf -i 20000-60000 -n 1)
PASS=$(openssl rand -base64 12 | tr -d /=+ | cut -c1-16)

# 获取IP
IP=$(curl -s ifconfig.me)

echo "端口: $PORT"
echo "密码: $PASS"
echo "IP: $IP"

# 安装 sing-box
bash <(curl -fsSL https://sing-box.app/install.sh)

# 创建目录
mkdir -p /etc/sing-box

# 写配置
cat > /etc/sing-box/config.json <<EOF
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
        "server_name": "apps.apple.com",
        "certificate_path": "/etc/sing-box/cert.pem",
        "key_path": "/etc/sing-box/key.pem"
      }
    }
  ],
  "outbounds": [{"type": "direct"}]
}
EOF

# 生成证书
openssl req -x509 -nodes -days 3650 \
-newkey rsa:2048 \
-keyout /etc/sing-box/key.pem \
-out /etc/sing-box/cert.pem \
-subj "/CN=apps.apple.com"

# 启动服务
systemctl enable sing-box
systemctl restart sing-box

# 开放端口
ufw allow $PORT/tcp >/dev/null 2>&1 || true
ufw allow $PORT/udp >/dev/null 2>&1 || true

# 生成 Trojan 链接
LINK="trojan://$PASS@$IP:$PORT?security=tls&sni=apps.apple.com&allowInsecure=1#Trojan-$IP"

echo ""
echo "====== 安装完成 ======"
echo ""
echo "节点链接："
echo "$LINK"
echo ""
