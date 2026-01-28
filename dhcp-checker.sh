#!/bin/bash

IFACE="ens37"
CONF="/etc/dhcp/dhcpd.conf"

echo "=== [1] Interface status ==="
ip a show "$IFACE" || exit 1

echo
echo "=== [2] Route check ==="
ip route | grep "$IFACE" || echo "⚠ No route bound to $IFACE"

echo
echo "=== [3] DHCP config syntax check ==="
dhcpd -t -cf "$CONF" || exit 1

echo
echo "=== [4] Running DHCP processes ==="
ps aux | grep '[d]hcpd' || echo "dhcpd not running"

echo
echo "=== [5] DEBUG MODE (CTRL+C to exit) ==="
echo ">>> Starting dhcpd foreground debug on $IFACE"
dhcpd -4 -d -cf "$CONF" "$IFACE"
# Note: To test DHCP functionality, use a client machine connected to the same network.