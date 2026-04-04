#!/bin/bash
# ip_forward_pumpkin.sh — Share laptop internet with Pumpkin 510 via USB gadget
#
# Usage: source ./ip_forward_pumpkin.sh

set -e

# Auto-detect the USB gadget interface (enx*)
IFACE=$(ip -o link show | grep -o 'enx[a-f0-9]*')
if [ -z "$IFACE" ]; then
    echo "ERROR: No USB gadget interface (enx*) found"
    exit 1
fi

# Get the laptop's IP on that interface
LAPTOP_IP=$(ip -4 -o addr show "$IFACE" | awk '{print $4}' | cut -d/ -f1)
if [ -z "$LAPTOP_IP" ]; then
    echo "ERROR: No IPv4 address on $IFACE"
    exit 1
fi

echo "USB gadget interface: $IFACE"
echo "Laptop IP: $LAPTOP_IP"

sudo sysctl net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -o wlp2s0 -j MASQUERADE
sudo iptables -A FORWARD -i "$IFACE" -j ACCEPT
sudo iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

echo ""
echo "On the Pumpkin, run:"
echo "  sudo ip route add default via $LAPTOP_IP"
echo "  echo 'nameserver 8.8.8.8' | sudo tee /etc/resolv.conf"
