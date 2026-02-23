#!/bin/bash
set -e

# ==============================
# SET DEBUG=1 untuk live debug
# ==============================
DEBUG=0

echo "=== DHCP SERVER AUTOMATION START ==="

###################################
# 1. INSTALL DHCP SERVER
###################################
echo "[1/5] Installing isc-dhcp-server..."

apt update
apt install -y isc-dhcp-server

###################################
# 2. CONFIGURE INTERFACES
###################################
echo "[2/5] Configuring DHCP interfaces..."

sed -i 's/^INTERFACESv4=.*/INTERFACESv4="ens37 ens38"/' \
  /etc/default/isc-dhcp-server

###################################
# 3. DHCP CONFIGURATION
###################################
echo "[3/5] Writing /etc/dhcp/dhcpd.conf..."

cat > /etc/dhcp/dhcpd.conf <<'EOF'
# Global DHCP Config
option domain-name "lks.local";
option domain-name-servers 192.168.30.2;

default-lease-time 600;
max-lease-time 7200;

authoritative;
ddns-update-style none;

# Subnet 192.168.30.0/24
subnet 192.168.30.0 netmask 255.255.255.0 {
    range 192.168.30.100 192.168.30.200;
    option routers 192.168.30.1;
    option subnet-mask 255.255.255.0;
    option broadcast-address 192.168.30.255;
    option domain-name-servers 192.168.30.2;
    option domain-name "lks.id";
}

# Subnet 192.168.40.0/24
subnet 192.168.40.0 netmask 255.255.255.0 {
    range 192.168.40.100 192.168.40.200;
    option routers 192.168.40.1;
    option subnet-mask 255.255.255.0;
    option broadcast-address 192.168.40.255;
    option domain-name-servers 192.168.30.2;
    option domain-name "lks.id";
}
EOF

###################################
# 4. DEBUG & VALIDATION
###################################
echo "[4/5] DHCP config syntax check..."
dhcpd -t -cf /etc/dhcp/dhcpd.conf

if [ "$DEBUG" -eq 1 ]; then
  echo "DEBUG MODE ENABLED"
  echo "Running dhcpd in foreground (Ctrl+C to stop)..."
  dhcpd -4 -d -cf /etc/dhcp/dhcpd.conf
  exit 0
fi

###################################
# 5. START SERVICE
###################################
echo "[5/5] Starting DHCP service..."

systemctl enable isc-dhcp-server
systemctl restart isc-dhcp-server

echo "=== DHCP SERVER SETUP COMPLETE ==="
systemctl status isc-dhcp-server --no-pager
