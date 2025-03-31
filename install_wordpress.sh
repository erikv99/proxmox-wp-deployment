#!/bin/bash

# Update packages
apt update && apt upgrade -y

# Install LAMP stack
apt install -y apache2 mysql-server php libapache2-mod-php php-mysql

# Configure MySQL
debconf-set-selections <<< 'mysql-server mysql-server/root_password password your_password'
debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password your_password'

# Create database
mysql -u root -pyour_password <<EOF
CREATE DATABASE wordpress;
CREATE USER 'wpuser'@'localhost' IDENTIFIED BY 'wppassword';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';
FLUSH PRIVILEGES;
EOF

# Download and install WordPress
cd /var/www/html
rm index.html
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* .
rm -rf wordpress latest.tar.gz
chown -R www-data:www-data /var/www/html/

# Configure WordPress
cp wp-config-sample.php wp-config.php
sed -i "s/database_name_here/wordpress/" wp-config.php
sed -i "s/username_here/wpuser/" wp-config.php
sed -i "s/password_here/wppassword/" wp-config.php

# Configure firewall
apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
echo "y" | ufw enable

# Create unique SSH user
useradd -m -s /bin/bash training_user
mkdir -p /home/training_user/.ssh
chmod 700 /home/training_user/.ssh
echo "ssh-rsa YOUR_PUBLIC_KEY" > /home/training_user/.ssh/authorized_keys
chmod 600 /home/training_user/.ssh/authorized_keys
chown -R training_user:training_user /home/training_user/.ssh

# Install monitoring agent
apt install -y prometheus-node-exporter
systemctl enable prometheus-node-exporter
systemctl start prometheus-node-exporter
