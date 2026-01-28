#!/bin/bash

echo "Editing /etc/network/interfaces"
nano /etc/network/interfaces

read -p "Press Enter to restart networking.service..."

systemctl restart networking.service

read -p "Press Enter to continue to IP forwarding setup..."

# Enable IP Forwarding
echo "Editing /etc/sysctl.conf"
nano /etc/sysctl.conf

read -p "Press Enter to apply sysctl settings..."

sysctl -p

read -p "Press Enter to finish..."

# Verify IP forwarding status
echo "Current IP forwarding status (1 = enabled, 0 = disabled):"
cat /proc/sys/net/ipv4/ip_forward

read -p "Press Enter to comtinue..."