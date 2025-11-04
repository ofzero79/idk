#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/gre6tun.conf"
SERVICE_FILE="/etc/systemd/system/gre6tun.service"
TUN_NAME="gre6tun"
TUN_MODE="ip6gre"
TUN_TTL=255
TUN_IPV4_LOCAL="192.168.166.1/30"
TUN_IPV4_PEER="192.168.166.2"

# گرفتن IPها از کاربر
if [[ ! -f "$CONFIG_FILE" ]]; then
  read -p "IPv6 ایران: " LOCAL_IPV6
  read -p "IPv6 خارج: " REMOTE_IPV6
  read -p "IPv4 ایران: " LOCAL_IPV4_PUBLIC
  cat > "$CONFIG_FILE" <<EOF
LOCAL_IPV6=$LOCAL_IPV6
REMOTE_IPV6=$REMOTE_IPV6
LOCAL_IPV4_PUBLIC=$LOCAL_IPV4_PUBLIC
EOF
else
  source "$CONFIG_FILE"
fi

# حذف تونل قدیمی
ip -6 tunnel show | grep -q "^${TUN_NAME}:" && ip -6 tunnel del "${TUN_NAME}" || true
modprobe ip6_gre || true

# ایجاد تونل و اختصاص آدرس
ip -6 tunnel add "${TUN_NAME}" mode "${TUN_MODE}" remote "${REMOTE_IPV6}" local "${LOCAL_IPV6}" ttl "${TUN_TTL}"
ip link set "${TUN_NAME}" up
ip addr add "${TUN_IPV4_LOCAL}" dev "${TUN_NAME}"

# فعال کردن ip_forward
sysctl -w net.ipv4.ip_forward=1

# iptables
iptables -t nat -A PREROUTING -p tcp --dport 22 -j DNAT --to-destination "${LOCAL_IPV4_PUBLIC}"
iptables -t nat -A PREROUTING -p tcp --dport 1:65535 -j DNAT --to-destination "${TUN_IPV4_PEER}:1-65535"
iptables -t nat -A PREROUTING -p udp --dport 1:65535 -j DNAT --to-destination "${TUN_IPV4_PEER}:1-65535"
iptables -t nat -A POSTROUTING -j MASQUERADE

# ساخت systemd unit
if [[ ! -f "$SERVICE_FILE" ]]; then
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=GRE6 Tunnel Setup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash -c 'bash $0'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable gre6tun.service
fi

# نمایش وضعیت
ip -6 tunnel show
ip addr show dev "${TUN_NAME}"
iptables -t nat -L -n -v
