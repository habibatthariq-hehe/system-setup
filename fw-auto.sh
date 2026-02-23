#!/bin/bash
set -e

echo "=== FW-SRV AUTOMATION START ==="

###################################
# 0. PRE-CHECK
###################################
echo "[0/8] Pre-check interface..."

for i in ens33 ens37 ens38; do
  ip link show "$i" >/dev/null 2>&1 || {
    echo "ERROR: Interface $i not found"
    exit 1
  }
done

###################################
# 1. NETWORK CONFIGURATION
###################################
echo "[1/8] Configuring network interfaces..."

cat > /etc/network/interfaces <<'EOF'
auto lo
iface lo inet loopback

auto ens33
allow-hotplug ens33
iface ens33 inet dhcp

auto ens37
allow-hotplug ens37
iface ens37 inet static
    address 192.168.30.1
    netmask 255.255.255.0

auto ens38
allow-hotplug ens38
iface ens38 inet static
    address 192.168.40.1
    netmask 255.255.255.0
EOF

systemctl restart networking || echo "Networking restart skipped"

###################################
# 2. INSTALL FIREWALL
###################################
echo "[2/8] Installing Firewalld..."

apt update
apt install -y firewalld iproute2 resolvconf

###################################
# 3. ENABLE FIREWALLD
###################################
echo "[3/8] Enabling Firewalld..."

systemctl enable firewalld
systemctl start firewalld

###################################
# 4. IP FORWARDING
###################################
echo "[4/8] Enabling IP forwarding..."

sed -i 's/^net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
grep -q net.ipv4.ip_forward /etc/sysctl.conf || \
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

sysctl -w net.ipv4.ip_forward=1

###################################
# 5. FIREWALLD ZONES & SERVICES
###################################
echo "[5/8] Configuring Firewalld zones..."

firewall-cmd --permanent --zone=external --change-interface=ens33
firewall-cmd --permanent --zone=internal --change-interface=ens37
firewall-cmd --permanent --zone=dmz --change-interface=ens38

firewall-cmd --permanent --zone=external --add-masquerade

for svc in dhcp dns http https ssh smtp pop3 imap; do
  firewall-cmd --permanent --zone=internal --add-service=$svc
done

for svc in http https smtp pop3 imap; do
  firewall-cmd --permanent --zone=dmz --add-service=$svc
done

###################################
# 6. FIREWALL POLICIES (UNCHANGED)
###################################
echo "[6/8] Applying firewall policies (unchanged)..."

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

###################################
# 7. PORT FORWARDING
###################################
echo "[7/8] Configuring port forwarding..."

firewall-cmd --permanent --zone=external \
  --add-forward-port=port=80:proto=tcp:toaddr=192.168.40.3:toport=80

firewall-cmd --permanent --zone=external \
  --add-forward-port=port=443:proto=tcp:toaddr=192.168.40.3:toport=443

firewall-cmd --permanent --zone=external \
  --add-forward-port=port=8080:proto=tcp:toaddr=192.168.40.4:toport=80

firewall-cmd --permanent --policy=dmz-to-lan \
  --add-rich-rule='rule family=ipv4 service name=dns accept'

firewall-cmd --permanent --zone=external --add-port=25/tcp
firewall-cmd --permanent --zone=external --add-port=80/tcp
firewall-cmd --permanent --zone=external --add-port=143/tcp

firewall-cmd --permanent --zone=dmz --add-service=smtp
firewall-cmd --permanent --zone=dmz --add-service=imap
firewall-cmd --permanent --zone=dmz --add-service=pop3

firewall-cmd --reload

echo "=== FW-SRV FIREWALL SETUP COMPLETE ==="
