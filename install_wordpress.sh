#!/bin/bash

# Update packages
apt update && apt upgrade -y

# Install LAMP stack with MariaDB instead of MySQL
apt install -y apache2 mariadb-server php libapache2-mod-php php-mysql

# Ensure Apache is running and directories exist
systemctl start apache2
systemctl enable apache2

if [ ! -d "/var/www/html" ]; then
  mkdir -p /var/www/html
fi

# Configure MariaDB
# Set root password
MYSQL_ROOT_PASSWORD="your_password"
mysqladmin -u root password "$MYSQL_ROOT_PASSWORD" || true

# Create database and user
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF || true
CREATE DATABASE IF NOT EXISTS wordpress;
CREATE USER IF NOT EXISTS 'wpuser'@'localhost' IDENTIFIED BY 'wppassword';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';
FLUSH PRIVILEGES;
EOF

# Download and install WordPress
cd /var/www/html
if [ -f index.html ]; then
  rm index.html
fi

wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* .
rm -rf wordpress latest.tar.gz
chown -R www-data:www-data /var/www/html/

# Configure WordPress
if [ -f wp-config-sample.php ]; then
  cp wp-config-sample.php wp-config.php
  sed -i "s/database_name_here/wordpress/" wp-config.php
  sed -i "s/username_here/wpuser/" wp-config.php
  sed -i "s/password_here/wppassword/" wp-config.php
  
  # Add unique security keys
  curl -s https://api.wordpress.org/secret-key/1.1/salt/ >> wp-config-keys.txt
  sed -n '/AUTH_KEY/,/NONCE_SALT/p' wp-config-keys.txt > wp-config-keys-clean.txt
  sed -i '/put your unique phrase here/d' wp-config.php
  sed -i "/define('AUTH_KEY'/r wp-config-keys-clean.txt" wp-config.php
  rm wp-config-keys.txt wp-config-keys-clean.txt
fi

# Configure firewall
apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
echo "y" | ufw enable || true

# Create unique SSH user
useradd -m -s /bin/bash training_user || true
mkdir -p /home/training_user/.ssh
chmod 700 /home/training_user/.ssh

# Vervang dit met jouw eigen SSH public key
echo "ssh-rsa YOUR_PUBLIC_KEY" > /home/training_user/.ssh/authorized_keys
chmod 600 /home/training_user/.ssh/authorized_keys
chown -R training_user:training_user /home/training_user/.ssh

# Add user to sudoers
echo "training_user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/training_user
chmod 440 /etc/sudoers.d/training_user

# Install monitoring agent if available
apt install -y prometheus-node-exporter || true
systemctl enable prometheus-node-exporter || true
systemctl start prometheus-node-exporter || true

echo "WordPress installation finished!"
