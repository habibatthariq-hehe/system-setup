#!/bin/bash
set -e

echo "=== BIND9 FORWARD ZONE (db.lks.id) SETUP START ==="

###################################
# 1. PRE-CHECK
###################################
echo "[1/4] Pre-check bind9..."

command -v named-checkzone >/dev/null 2>&1 || {
  echo "ERROR: bind9utils not installed"
  exit 1
}

###################################
# 2. WRITE db.lks.id
###################################
echo "[2/4] Writing /etc/bind/db.lks.id..."

cat > /etc/bind/db.lks.id <<'EOF'
$TTL    604800
@       IN      SOA     ns.lks.id. admin.lks.id. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@               IN      NS      ns.lks.id.

gateway         IN      A       192.168.30.1
fw              IN      A       192.168.30.1
fw-srv          IN      A       192.168.30.1

ns              IN      A       192.168.30.2
internal        IN      A       192.168.30.2
internal-srv    IN      A       192.168.30.2

mail            IN      A       192.168.40.2
mail-srv        IN      A       192.168.40.2

web01           IN      A       192.168.40.3
web02           IN      A       192.168.40.3

www             IN      CNAME   web01.lks.id.
webmail         IN      CNAME   mail.lks.id.
EOF

###################################
# 3. VALIDATE ZONE
###################################
echo "[3/4] Validating zone file..."

named-checkzone lks.id /etc/bind/db.lks.id

###################################
# 4. RESTART BIND
###################################
echo "[4/4] Restarting bind9..."

systemctl restart bind9

echo "=== db.lks.id SETUP COMPLETE ==="
systemctl status bind9 --no-pager
