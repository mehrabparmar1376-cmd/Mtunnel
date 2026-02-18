#!/bin/bash

clear
echo "====== MTunnel Wizard v1 ======"

# نصب پیش‌نیازها
echo "Installing dependencies..."
apt update -y >/dev/null 2>&1
apt install -y iproute2 iptables curl >/dev/null 2>&1

# تشخیص IP عمومی
LOCAL_IP=$(curl -s ipv4.icanhazip.com)
echo "Detected Public IP: $LOCAL_IP"

# انتخاب نوع سرور
echo ""
echo "Select Server Type:"
echo "1) IRAN Server"
echo "2) FOREIGN Server"
read -p "Enter choice [1-2]: " TYPE

# گرفتن IP سرور مقابل
read -p "Enter Remote Public IP: " REMOTE_IP

# تنظیمات GRE
TUN_DEV="mtun"
SUBNET="10.200.200.0/30"

if [ "$TYPE" == "1" ]; then
    LOCAL_TUN_IP="10.200.200.1/30"
    REMOTE_TUN_IP="10.200.200.2"
else
    LOCAL_TUN_IP="10.200.200.2/30"
    REMOTE_TUN_IP="10.200.200.1"
fi

# حذف GRE قبلی در صورت وجود
ip tunnel del $TUN_DEV 2>/dev/null

# ساخت GRE
echo "Creating GRE Tunnel..."
ip tunnel add $TUN_DEV mode gre remote $REMOTE_IP local $LOCAL_IP ttl 255
ip addr add $LOCAL_TUN_IP dev $TUN_DEV
ip link set $TUN_DEV mtu 1476
ip link set $TUN_DEV up

# فعال کردن IP Forward
echo 1 > /proc/sys/net/ipv4/ip_forward

# NAT برای عبور ترافیک
echo "Setting NAT..."
iptables -t nat -A POSTROUTING -o $TUN_DEV -j MASQUERADE

# ساخت systemd سرویس برای auto restart
cat > /etc/systemd/system/mtunnel.service <<EOF
[Unit]
Description=MTunnel Service
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash /root/mtunnel.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mtunnel

# پیام پایانی
clear
echo "====== MTunnel Setup Complete ======"
echo "Local Tunnel IP: $LOCAL_TUN_IP"
echo "Remote Tunnel IP: $REMOTE_TUN_IP"
echo ""
echo "Test connectivity: ping $REMOTE_TUN_IP"
echo ""
echo "Wizard finished. Service enabled for auto start."
