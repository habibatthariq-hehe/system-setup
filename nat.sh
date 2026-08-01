#!/bin/bash

# Remove set -e temporarily to handle errors gracefully with our own trap
# set -e 

# ==========================================
# ROOT PRIVILEGE CHECK
# ==========================================
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: Please run this script as root (or use sudo)."
  exit 1
fi

echo "=========================================="
echo "      NAT CONFIGURATION & AUTOMATION      "
echo "=========================================="
echo ""
echo "=== 1/9 INTERFACE & IP CONFIGURATION ==="
echo "You can use a predefined template setup or configure values manually."
echo "Template settings:"
echo "  - WAN Interface: eth0"
echo "  - LAN Interface: eth1 (IP: 192.168.30.1)"
echo "  - DMZ Interface: eth2 (IP: 192.168.40.1)"
echo "  - Netmask:       255.255.255.0"
echo ""

read -p "Do you want to use this template setup? (y/n) [y]: " USE_TEMPLATE

if [[ -z "$USE_TEMPLATE" || "$USE_TEMPLATE" =~ ^[yY]$ ]]; then
  echo "Applying template setup..."
  EXT_IF="eth0"
  INT_IF="eth1"
  INT_IP="192.168.30.1"
  DMZ_IF="eth2"
  DMZ_IP="192.168.40.1"
  NETMASK="255.255.255.0"
else
  echo ""
  echo "--- Manual Configuration ---"
  read -p "Enter External (WAN) Interface (e.g., eth0): " EXT_IF
  EXT_IF=${EXT_IF:-eth0}

  read -p "Enter Internal (LAN) Interface (e.g., eth1): " INT_IF
  INT_IF=${INT_IF:-eth1}
  read -p "Enter Internal IP Address (e.g., 192.168.30.1): " INT_IP
  INT_IP=${INT_IP:-192.168.30.1}

  read -p "Enter DMZ Interface (e.g., eth2): " DMZ_IF
  DMZ_IF=${DMZ_IF:-eth2}
  read -p "Enter DMZ IP Address (e.g., 192.168.40.1): " DMZ_IP
  DMZ_IP=${DMZ_IP:-192.168.40.1}

  read -p "Enter Netmask (e.g., 255.255.255.0): " NETMASK
  NETMASK=${NETMASK:-255.255.255.0}
fi

echo ""
echo "=== 2/9 PRE-CHECK INTERFACES ==="
for i in "$EXT_IF" "$INT_IF" "$DMZ_IF"; do
  if ! ip link show "$i" >/dev/null 2>&1; then
    echo "ERROR: Interface $i not found! Please check your hardware."
    exit 1
  fi
done
echo "All required interfaces detected ($EXT_IF, $INT_IF, $DMZ_IF)."

# ==========================================
# BACKUP & ROLLBACK FUNCTIONALITY
# ==========================================
INTF_BAK="/etc/network/interfaces.bak.$(date +%s)"
SYSCTL_BAK="/etc/sysctl.conf.bak.$(date +%s)"

echo ""
echo "=== 3/9 CREATING BACKUPS (FOR ROLLBACK) ==="
[ -f /etc/network/interfaces ] && cp /etc/network/interfaces "$INTF_BAK"
[ -f /etc/sysctl.conf ] && cp /etc/sysctl.conf "$SYSCTL_BAK"
echo "Backups created successfully."

rollback() {
  echo ""
  echo "!!! INITIATING ROLLBACK !!!"
  echo "Restoring configuration files..."
  [ -f "$INTF_BAK" ] && mv "$INTF_BAK" /etc/network/interfaces
  [ -f "$SYSCTL_BAK" ] && mv "$SYSCTL_BAK" /etc/sysctl.conf
  
  echo "Disabling IP forwarding..."
  sysctl -w net.ipv4.ip_forward=0 >/dev/null 2>&1
  
  echo "Restarting networking..."
  systemctl restart networking >/dev/null 2>&1 || true
  
  echo "Stopping and disabling firewalld..."
  systemctl disable --now firewalld >/dev/null 2>&1 || true
  
  echo "Rollback complete. System returned to previous state."
  exit 1
}

# Trap unexpected exits or script interruptions to trigger rollback
trap 'echo "Script interrupted or failed! Triggering rollback..."; rollback' ERR SIGINT SIGTERM

echo ""
echo "=== 4/9 DETECTING PACKAGE MANAGER ==="
PKG_MANAGERS=()

command -v apt >/dev/null 2>&1 && PKG_MANAGERS+=("apt")
command -v dnf >/dev/null 2>&1 && PKG_MANAGERS+=("dnf")
command -v yum >/dev/null 2>&1 && PKG_MANAGERS+=("yum")
command -v pacman >/dev/null 2>&1 && PKG_MANAGERS+=("pacman")
command -v zypper >/dev/null 2>&1 && PKG_MANAGERS+=("zypper")

if [ ${#PKG_MANAGERS[@]} -eq 0 ]; then
  echo "ERROR: No supported package manager found."
  false # triggers trap
fi

if [ ${#PKG_MANAGERS[@]} -eq 1 ]; then
  PKG="${PKG_MANAGERS[0]}"
  echo "Detected package manager: $PKG"
else
  echo "Multiple package managers detected:"
  select PKG in "${PKG_MANAGERS[@]}"; do
    if [ -n "$PKG" ]; then
      break
    else
      echo "Invalid selection"
    fi
  done
fi

echo ""
echo "=== 5/9 INSTALLING DEPENDENCIES ==="
case $PKG in
  apt)
    apt update
    apt install -y firewalld iproute2 resolvconf
    ;;
  dnf)
    dnf install -y firewalld iproute2 resolvconf
    ;;
  yum)
    yum install -y firewalld iproute2 resolvconf
    ;;
  pacman)
    pacman -Sy --noconfirm firewalld iproute2 resolvconf
    ;;
  zypper)
    zypper install -y firewalld iproute2 resolvconf
    ;;
esac

echo ""
echo "=== 6/9 CONFIGURING NETWORK INTERFACES ==="
cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto $EXT_IF
allow-hotplug $EXT_IF
iface $EXT_IF inet dhcp

auto $INT_IF
allow-hotplug $INT_IF
iface $INT_IF inet static
    address $INT_IP
    netmask $NETMASK

auto $DMZ_IF
allow-hotplug $DMZ_IF
iface $DMZ_IF inet static
    address $DMZ_IP
    netmask $NETMASK
EOF

systemctl restart networking || echo "WARNING: Networking restart skipped (may not be supported on this OS)."

echo ""
echo "=== 7/9 ENABLING FIREWALLD & IP FORWARDING ==="
systemctl enable --now firewalld

sed -i 's/^net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -w net.ipv4.ip_forward=1

echo ""
echo "=== 8/9 CONFIGURING FIREWALL ZONES & POLICIES ==="
firewall-cmd --permanent --zone=external --change-interface="$EXT_IF"
firewall-cmd --permanent --zone=internal --change-interface="$INT_IF"
firewall-cmd --permanent --zone=dmz --change-interface="$DMZ_IF"

firewall-cmd --permanent --zone=external --add-masquerade

for svc in dhcp dns http https ssh smtp pop3 imap; do
  firewall-cmd --permanent --zone=internal --add-service="$svc"
done

for svc in http https smtp pop3 imap; do
  firewall-cmd --permanent --zone=dmz --add-service="$svc"
done

# Policies
firewall-cmd --permanent --new-policy=int-to-ext || true
firewall-cmd --permanent --policy=int-to-ext --add-ingress-zone=internal
firewall-cmd --permanent --policy=int-to-ext --add-egress-zone=external
firewall-cmd --permanent --policy=int-to-ext --set-target=ACCEPT

firewall-cmd --permanent --new-policy=int-to-int || true
firewall-cmd --permanent --policy=int-to-int --add-ingress-zone=internal
firewall-cmd --permanent --policy=int-to-int --add-egress-zone=internal
firewall-cmd --permanent --policy=int-to-int --set-target=ACCEPT

firewall-cmd --permanent --new-policy=lan-to-wan || true
firewall-cmd --permanent --policy=lan-to-wan --add-ingress-zone=internal
firewall-cmd --permanent --policy=lan-to-wan --add-egress-zone=external
firewall-cmd --permanent --policy=lan-to-wan --set-target=ACCEPT

firewall-cmd --permanent --new-policy=dmz-to-wan || true
firewall-cmd --permanent --policy=dmz-to-wan --add-ingress-zone=dmz
firewall-cmd --permanent --policy=dmz-to-wan --add-egress-zone=external
firewall-cmd --permanent --policy=dmz-to-wan --set-target=ACCEPT

firewall-cmd --permanent --new-policy=dmz-to-lan || true
firewall-cmd --permanent --policy=dmz-to-lan --add-ingress-zone=dmz
firewall-cmd --permanent --policy=dmz-to-lan --add-egress-zone=internal
firewall-cmd --permanent --policy=dmz-to-lan --set-target=DROP

# Port Forwarding
firewall-cmd --permanent --zone=external --add-forward-port=port=80:proto=tcp:toaddr=192.168.40.3:toport=80
firewall-cmd --permanent --zone=external --add-forward-port=port=443:proto=tcp:toaddr=192.168.40.3:toport=443
firewall-cmd --permanent --zone=external --add-forward-port=port=8080:proto=tcp:toaddr=192.168.40.4:toport=80

# DMZ Extras
firewall-cmd --permanent --policy=dmz-to-lan --add-rich-rule='rule family=ipv4 service name=dns accept'

firewall-cmd --permanent --zone=external --add-port=25/tcp
firewall-cmd --permanent --zone=external --add-port=80/tcp
firewall-cmd --permanent --zone=external --add-port=143/tcp

firewall-cmd --permanent --zone=dmz --add-service=smtp
firewall-cmd --permanent --zone=dmz --add-service=imap
firewall-cmd --permanent --zone=dmz --add-service=pop3

firewall-cmd --reload

# Disable ERR trap since we made it through the risky configuration phase
trap - ERR SIGINT SIGTERM

echo ""
echo "=== 9/9 TESTING NAT CONNECTIVITY ==="
echo "- IP Forwarding Check: $(sysctl -n net.ipv4.ip_forward)"
echo "- Masquerade Check: $(firewall-cmd --zone=external --query-masquerade)"

echo "- Testing direct internet connection..."
ping -c 2 8.8.8.8 >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "  [OK] Router can reach the internet."
else
    echo "  [FAIL] Router cannot reach the internet (check your default gateway)."
fi

echo "- Testing NAT (Ping 8.8.8.8 masquerading from $INT_IF)..."
ping -I "$INT_IF" -c 2 8.8.8.8 >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "  [OK] NAT translation is working! $INT_IF can communicate out."
else
    echo "  [FAIL] NAT test failed. Internal network cannot reach external network."
fi

echo ""
echo "=== NAT SETUP COMPLETE ==="
read -p "Are you satisfied with this configuration? (y/n): " CONFIRM
if [[ "$CONFIRM" =~ ^[nN]$ ]]; then
    rollback
else
    echo "Configuration accepted! Removing backup files to save space..."
    rm -f "$INTF_BAK" "$SYSCTL_BAK"
    echo "Done."
fi