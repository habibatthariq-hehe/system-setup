#!/bin/bash
set -e


###################################
# 1. INSTALL BIND9
###################################
echo "[1/6] Installing bind9..."

apt update
apt install -y bind9 bind9utils dnsutils

###################################
# 2. CONFIGURE named.conf.local
###################################
echo "[2/6] Writing named.conf.local..."

cat > /etc/bind/named.conf.local <<'EOF'
zone "lks.id" {
    type master;
    file "/etc/bind/db.lks.id";
};

zone "30.168.192.in-addr.arpa" {
    type master;
    file "/etc/bind/db.192.168.30";
};

zone "40.168.192.in-addr.arpa" {
    type master;
    file "/etc/bind/db.192.168.40";
};
EOF

###################################
# 3. FORWARD ZONE FILE
###################################
echo "[3/6] Creating forward zone file..."

cat > /etc/bind/db.lks.id <<'EOF'
$TTL    604800
@       IN      SOA     ns1.lks.id. admin.lks.id. (
                              2026020301 ; Serial
                              604800     ; Refresh
                              86400      ; Retry
                              2419200    ; Expire
                              604800 )   ; Negative Cache TTL
;
@       IN      NS      ns1.lks.id.
ns1     IN      A       192.168.30.2

fw-srv  IN      A       192.168.30.1
web-01  IN      A       192.168.40.3
mail    IN      A       192.168.30.4
EOF

###################################
# 4. REVERSE ZONE 192.168.30.0/24
###################################
echo "[4/6] Creating reverse zone 192.168.30.0/24..."

cat > /etc/bind/db.192.168.30 <<'EOF'
$TTL    604800
@       IN      SOA     ns1.lks.id. admin.lks.id. (
                              2026020301
                              604800
                              86400
                              2419200
                              604800 )
;
@       IN      NS      ns1.lks.id.
2       IN      PTR     ns1.lks.id.
1       IN      PTR     fw-srv.lks.id.
4       IN      PTR     mail.lks.id.
EOF

###################################
# 5. REVERSE ZONE 192.168.40.0/24
###################################
echo "[5/6] Creating reverse zone 192.168.40.0/24..."

cat > /etc/bind/db.192.168.40 <<'EOF'
$TTL    604800
@       IN      SOA     ns1.lks.id. admin.lks.id. (
                              2026020301
                              604800
                              86400
                              2419200
                              604800 )
;
@       IN      NS      ns1.lks.id.
3       IN      PTR     web-01.lks.id.
EOF

###################################
# 6. VALIDATION & START
###################################
echo "[6/6] Validating BIND configuration..."

named-checkconf
named-checkzone lks.id /etc/bind/db.lks.id
named-checkzone 30.168.192.in-addr.arpa /etc/bind/db.192.168.30
named-checkzone 40.168.192.in-addr.arpa /etc/bind/db.192.168.40

systemctl enable bind9
systemctl restart bind9

echo "=== BIND9 ZONE SETUP COMPLETE ==="
systemctl status bind9 --no-pager
