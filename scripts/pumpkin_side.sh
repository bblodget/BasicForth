#!/bin/bash
# pumpkin_side.sh — Set up internet access via USB gadget to laptop
#
# Usage: sudo ./pumpkin_side.sh

set -e

# The laptop's IP is the other host on the 192.168.96.0/24 subnet.
# The Pumpkin is always .1, so find the laptop by looking at ARP/neighbors.
GATEWAY=$(ip neigh show dev usb0 | awk '{print $1}' | head -1)

# Fallback: scan the subnet for the gateway
if [ -z "$GATEWAY" ]; then
    # Ping broadcast to populate ARP table
    ping -c 1 -b 192.168.96.255 >/dev/null 2>&1 || true
    sleep 0.5
    GATEWAY=$(ip neigh show dev usb0 | grep -v FAILED | awk '{print $1}' | head -1)
fi

if [ -z "$GATEWAY" ]; then
    echo "ERROR: Could not detect laptop gateway on usb0"
    echo "Make sure the USB cable is connected and ip_forward_pumpkin.sh was run on the laptop"
    exit 1
fi

echo "Detected gateway: $GATEWAY"

# Remove existing default route if any
ip route del default 2>/dev/null || true

ip route add default via "$GATEWAY"
echo "nameserver 8.8.8.8" | tee /etc/resolv.conf

echo ""
ping -c 2 8.8.8.8
