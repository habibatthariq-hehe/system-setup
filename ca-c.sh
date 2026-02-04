set -e

echo "========================================"
echo " LKS INTERNAL CA + SERVER CERT SETUP"
echo "========================================"
echo
sleep 3

############################################
# SECTION 1 — CREATE CA SERVER
############################################
echo "========== SECTION 1: CREATE CA =========="
sleep 2

echo "[1.1] Creating CA directory structure..."
mkdir -p /root/ca/{certs,crl,newcerts,private}
chmod 700 /root/ca/private
touch /root/ca/index.txt
echo 1000 > /root/ca/serial

echo "OK: CA directory structure ready"
sleep 2

echo "[1.2] Creating OpenSSL configuration file..."

cat > /root/ca/openssl.cnf <<'EOF'
[ ca ]
default_ca = CA_default

[ CA_default ]
dir             = /root/ca
certs           = $dir/certs
crl_dir         = $dir/crl
new_certs_dir   = $dir/newcerts
database        = $dir/index.txt
serial          = $dir/serial
private_key     = $dir/private/ca.key
certificate     = $dir/certs/ca.crt
default_md      = sha256
policy          = policy_any
x509_extensions = v3_ca
default_days    = 3650

[ policy_any ]
commonName = supplied

[ req ]
default_bits       = 4096
distinguished_name = req_distinguished_name
string_mask        = utf8only

[ req_distinguished_name ]
commonName = Common Name

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

echo "OK: openssl.cnf created"
sleep 2

echo "[1.3] Generating CA private key..."
openssl genrsa -out /root/ca/private/ca.key 4096

echo "[1.4] Generating ROOT CA certificate..."
openssl req -x509 -new -nodes \
  -key /root/ca/private/ca.key \
  -sha256 -days 3650 \
  -out /root/ca/certs/ca.crt \
  -subj "/CN=LKS-ROOT-CA"

echo "ROOT CA successfully created!"
echo "CA certificate file: /root/ca/certs/ca.crt"
sleep 3

############################################
# SECTION 2 — SERVER CERTIFICATE
############################################
echo
echo "========== SECTION 2: SERVER CERTIFICATE =========="
sleep 2

SERVER_NAME="mail.lks.id"

echo "[2.1] Generating private key and CSR for $SERVER_NAME..."
openssl genrsa -out $SERVER_NAME.key 2048
openssl req -new -key $SERVER_NAME.key -out $SERVER_NAME.csr \
  -subj "/CN=$SERVER_NAME"

echo "[2.2] Signing CSR using the CA..."
openssl ca -config /root/ca/openssl.cnf \
  -in $SERVER_NAME.csr \
  -out $SERVER_NAME.crt \
  -batch

echo "Server certificate successfully created:"
echo " - $SERVER_NAME.crt"
echo " - CA certificate (ca.crt)"
sleep 3

############################################
# SECTION 3 — APACHE SSL
############################################
echo
echo "========== SECTION 3: APACHE SSL =========="
sleep 2

echo "[3.1] Enabling Apache SSL module..."
a2enmod ssl
systemctl restart apache2

echo "[3.2] Copying certificates to SSL directories..."
cp $SERVER_NAME.crt /etc/ssl/certs/
cp $SERVER_NAME.key /etc/ssl/private/
chmod 600 /etc/ssl/private/$SERVER_NAME.key

echo "[3.3] Creating HTTPS VirtualHost configuration..."

cat > /etc/apache2/sites-available/mail-ssl.conf <<EOF
<VirtualHost *:443>
    ServerName $SERVER_NAME
    DocumentRoot /var/lib/roundcube

    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/$SERVER_NAME.crt
    SSLCertificateKeyFile /etc/ssl/private/$SERVER_NAME.key
</VirtualHost>
EOF

a2ensite mail-ssl
systemctl reload apache2

echo "Apache HTTPS is now active"
sleep 2

cat > /root/ca/db.lks.id <<'EOF'
$TTL    604800
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
