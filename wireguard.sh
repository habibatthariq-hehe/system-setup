#!/bin/bash
set -e

echo "=== WIREGUARD VPN SETUP START ==="

###################################
# 1. INSTALL WIREGUARD
###################################
echo "[1/4] Installing WireGuard..."

apt update
apt install -y wireguard

###################################
# 2. KEY GENERATION
###################################
echo "[2/4] Generating keys..."

mkdir -p /etc/wireguard
cd /etc/wireguard

if [ ! -f server.key ]; then
  wg genkey | tee server.key | wg pubkey > server.pub
  wg genkey | tee client1.key | wg pubkey > client1.pub
  chmod 600 *.key
fi

###################################
# 3. CONFIGURATION
###################################
echo "[3/4] Writing wg0.conf..."

SERVER_KEY=$(cat server.key)
CLIENT1_PUB=$(cat client1.pub)

cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.10.10.1/24
ListenPort = 51820
PrivateKey = $SERVER_KEY
SaveConfig = true

[Peer]
PublicKey = $CLIENT1_PUB
AllowedIPs = 10.10.10.2/32
EOF

###################################
# 4. ENABLE & START
###################################
echo "[4/4] Enabling WireGuard..."

systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

echo "=== WIREGUARD SETUP COMPLETE ==="
echo "Server public key:"
cat /etc/wireguard/server.pub
