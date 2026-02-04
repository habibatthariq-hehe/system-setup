#!/bin/bash
set -e

echo "=== MAIL SERVER AUTOMATION START ==="
echo "WARNING: choose NO for database setup when prompted!"
echo "Configure database must be set to NO!"
echo "Please wait for 5 seconds"
sleep 5

###################################
# 1. SET HOSTNAME
###################################
echo "[1/9] Setting hostname..."

hostnamectl set-hostname mail.lks.id
hostname

sleep 5
getent hosts mail.lks.id || echo "WARNING: DNS for mail.lks.id not found yet"

echo "Please wait for 5 seconds"
sleep 5

###################################
# 2. INSTALL PACKAGES
###################################
echo "[2/9] Installing mail packages..."

apt update
apt install postfix dovecot-core dovecot-imapd dovecot-pop3d mailutils -y

echo "Please wait for 5 seconds"
sleep 5

echo "[3/9] Installing Roundcube..."
echo "⚠️  REMINDER: choose NO for database setup!"

apt install roundcube roundcube-core roundcube-mysql -y

echo "Please wait for 5 seconds"
sleep 5

###################################
# 3. CONFIGURE POSTFIX
###################################
echo "[4/9] Configuring Postfix..."

postconf -e "myhostname = mail.lks.id"
postconf -e "mydomain = lks.id"
postconf -e "myorigin = \$mydomain"

postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"

postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
postconf -e "home_mailbox = Maildir/"

systemctl restart postfix
systemctl enable postfix

postconf -n

###################################
# 4. CONFIGURE DOVECOT MAILDIR
###################################
echo "[5/9] Configuring Dovecot mail location..."

sed -i 's|^#\?mail_location =.*|mail_location = maildir:~/Maildir|' \
  /etc/dovecot/conf.d/10-mail.conf

###################################
# 5. CONFIGURE DOVECOT AUTH
###################################
echo "[6/9] Configuring Dovecot authentication..."

sed -i 's/^#\?disable_plaintext_auth =.*/disable_plaintext_auth = no/' \
  /etc/dovecot/conf.d/10-auth.conf

sed -i 's/^#\?auth_mechanisms =.*/auth_mechanisms = plain login/' \
  /etc/dovecot/conf.d/10-auth.conf

###################################
# 6. ENABLE & START DOVECOT
###################################
echo "[7/9] Enabling Dovecot..."

systemctl enable dovecot
systemctl restart dovecot

###################################
# 7. ENABLE ROUNDCUBE APACHE CONF
###################################
echo "[8/9] Enabling Roundcube Apache config..."

a2enconf roundcube
systemctl restart apache2

###################################
# 8. FINAL CHECK
###################################
echo "[9/9] Final service status..."

systemctl --no-pager status postfix | head -n 5
systemctl --no-pager status dovecot | head -n 5
systemctl --no-pager status apache2 | head -n 5

echo "=== MAIL SERVER SETUP COMPLETE ==="
