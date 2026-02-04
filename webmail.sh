#!/bin/bash
echo "Configure database must be set to no!"
echo "Please wait for 5 seconds"
sleep 5

hostnamectl set-hostname mail.lks.id
hostname
echo "Please wait for 5 seconds"
sleep 5

getent hosts mail.lks.id
echo "Please wait for 5 seconds"
sleep 5

apt install postfix dovecot-core dovecot-imapd dovecot-pop3d mailutils -y
echo "Please wait for 5 seconds"
sleep 5

apt install roundcube roundcube-core roundcube-mysql -y
echo "Please wait for 5 seconds"
sleep 5

/usr/sbin/a2enconf roundcube
systemctl restart apache2