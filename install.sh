#!/bin/bash

clear
echo "====== MTunnel Pro Wizard v1 (Final) ======"
echo ""

# نصب پیش‌نیازها
echo "[*] Installing dependencies..."
apt update -y >/dev/null 2>&1
apt install -y iproute2 iptables curl >/dev/null 2>&1

# تشخیص IP عمومی سرور
LOCAL_IP=$(curl -s ipv4.icanhazip.com)
echo "[*] Detected Public IP: $LOCAL_IP"
echo ""

# تعداد سرورهایی که میخوای متصل کنی
read -p "Enter number of servers to connect (1-5): " SERVER_COUNT

declare -a SERVER_IPS
declare -a TUN_LOCAL_IPS
declare -a TUN_REMOTE_IPS

# گرفتن اطلاعات سرورها
for ((i=1; i<=SERVER_COUNT; i++))
do
    echo ""
    read -p "Enter Server #$i type (1=IRAN, 2=FOREIGN): " SERVER_TYPE
    read -p "Enter Remote Public IP for Server #$i: " REMOTE_IP

    if [ "$SERVER_TYPE" == "1" ]; then
        LOCAL_TUN="10.200.200.$((i*2-1))/30"
        REMOTE_TUN="10.200.200.$((i*2))"
    else
        LOCAL_TUN="10.200.200.$((i*2))/30"
        REMOTE_TUN="10.200.200.$((i*2-1))"
    fi

    SERVER_IPS[$i]=$REMOTE_IP
    TUN_LOCAL_IPS[$i]=$LOCAL_TUN
    TUN_REMOTE_IPS[$i]=$REMOTE_TUN
done

echo ""
# انتخاب پروتکل
echo "Select Protocol:"
echo "1) TCP"
echo "2) UDP"
read -p "Enter choice [1-2]: " PROTOCOL

# انتخاب پورت‌ها برای Port Forward
read -p "Enter ports to forward (single or range, e.g., 443 or 5000-5010): " PORTS

echo ""
echo "[*] Creating Tunnels..."
for ((i=1; i<=SERVER_COUNT; i++))
do
    TUN_DEV="mtun$i"
    REMOTE_IP=${SERVER_IPS[$i]}
    LOCAL_TUN_IP=${TUN_LOCAL_IPS[$i]}
    REMOTE_TUN_IP=${TUN_REMOTE_IPS[$i]}

    ip tunnel del $TUN_DEV 2>/dev/null
    ip tunnel add $TUN_DEV mode gre remote $REMOTE_IP local $LOCAL_IP ttl 255
    ip addr add $LOCAL_TUN_IP dev $TUN_DEV
    ip link set $TUN_DEV mtu 1476
    ip link set $TUN_DEV up

    echo "[*] Tunnel $TUN_DEV created: $LOCAL_TUN_IP <-> $REMOTE_TUN_IP"

    # NAT
    iptables -t nat -A POSTROUTING -o $TUN_DEV -j MASQUERADE

    # Port Forwarding
    if [[ $PORTS == *-* ]]; then
        # range
        START_PORT=$(echo $PORTS | cut -d- -f1)
        END_PORT=$(echo $PORTS | cut -d- -f2)
        for ((p=START_PORT; p<=END_PORT; p++)); do
            iptables -t nat -A PREROUTING -p $PROTOCOL --dport $p -j DNAT --to-destination $REMOTE_TUN_IP:$p
        done
    else
        # single port
        iptables -t nat -A PREROUTING -p $PROTOCOL --dport $PORTS -j DNAT --to-destination $REMOTE_TUN_IP:$PORTS
    fi
done

# فعال کردن IP Forward
echo 1 > /proc/sys/net/ipv4/ip_forward

# ساخت سرویس systemd
cat > /etc/systemd/system/mtunnel.service <<EOF
[Unit]
Description=MTunnel Pro Service
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
echo "====== MTunnel Pro Setup Complete ======"
for ((i=1; i<=SERVER_COUNT; i++))
do
    echo "Tunnel mtun$i: ${TUN_LOCAL_IPS[$i]} <-> ${TUN_REMOTE_IPS[$i]}"
done
echo ""
echo "Test connectivity: ping <Remote Tunnel IP>"
echo "Wizard finished. Service enabled for auto start."
