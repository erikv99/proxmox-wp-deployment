#!/bin/bash

# Controleer of container ID is doorgegeven
if [ -z "$1" ]; then
  echo "Usage: $0 <container_id>"
  exit 1
fi

CONTAINER_ID=$1
CONTAINER_NUM=$(($CONTAINER_ID - 100 + 1))  
SSH_USER="wpuser_${CONTAINER_NUM}"
SSH_PASS="securePass_${CONTAINER_NUM}"  # Niet safe ofc, maar prima voor deze oplevering.
DB_USER="wpdbuser_${CONTAINER_NUM}"
DB_PASS="wpdbpass_${CONTAINER_NUM}"
ROOT_PASS="rootpass_${CONTAINER_NUM}"

# Maak een installatiescript dat in de container wordt uitgevoerd
cat > /tmp/wp_install_${CONTAINER_ID}.sh << 'EOF'
#!/bin/bash

# Parameters die worden vervangen door het hoofdscript
SSH_USER="__SSH_USER__"
SSH_PASS="__SSH_PASS__"
DB_USER="__DB_USER__"
DB_PASS="__DB_PASS__"
ROOT_PASS="__ROOT_PASS__"
CONTAINER_NUM="__CONTAINER_NUM__"

# Update packages
apt update && apt upgrade -y

# Install LAMP stack
apt install -y apache2 mariadb-server php libapache2-mod-php php-mysql

# Ensure Apache is running
systemctl start apache2
systemctl enable apache2

# Configure MariaDB
mysqladmin -u root password "$ROOT_PASS" || true

# Create database and user
mysql -u root -p"$ROOT_PASS" <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS wordpress;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON wordpress.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

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
cp wp-config-sample.php wp-config.php
sed -i "s/database_name_here/wordpress/" wp-config.php
sed -i "s/username_here/$DB_USER/" wp-config.php
sed -i "s/password_here/$DB_PASS/" wp-config.php

# Generate unique security keys
curl -s https://api.wordpress.org/secret-key/1.1/salt/ > /tmp/wp-keys
sed -i "/define( 'AUTH_KEY'/,/define( 'NONCE_SALT'/d" wp-config.php
sed -i "/put your unique phrase here/d" wp-config.php
sed -i "/That's all, stop editing/i $(cat /tmp/wp-keys)" wp-config.php
rm /tmp/wp-keys

# Install and configure firewall
apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp  # SSH
ufw allow 80/tcp  # HTTP
ufw allow 443/tcp # HTTPS
ufw allow 9100/tcp # Prometheus Node Exporter

echo "y" | ufw enable

# Create unique SSH user with key-based authentication
useradd -m -s /bin/bash $SSH_USER
echo "$SSH_USER:$SSH_PASS" | chpasswd
mkdir -p /home/$SSH_USER/.ssh
chmod 700 /home/$SSH_USER/.ssh

# Generate SSH key pair for this specific user
ssh-keygen -t rsa -b 4096 -f /home/$SSH_USER/.ssh/id_rsa -N ""
cat /home/$SSH_USER/.ssh/id_rsa.pub > /home/$SSH_USER/.ssh/authorized_keys
chmod 600 /home/$SSH_USER/.ssh/authorized_keys
chown -R $SSH_USER:$SSH_USER /home/$SSH_USER/.ssh

# Copy private key to accessible location for later retrieval
mkdir -p /root/ssh_keys
cp /home/$SSH_USER/.ssh/id_rsa /root/ssh_keys/${SSH_USER}_key
chmod 600 /root/ssh_keys/${SSH_USER}_key

# Add user to sudoers
echo "$SSH_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$SSH_USER
chmod 440 /etc/sudoers.d/$SSH_USER

# Install monitoring agent (Prometheus Node Exporter)
apt install -y prometheus-node-exporter

# Configure Node Exporter to listen on all interfaces
cat > /etc/default/prometheus-node-exporter << 'NODEEXP'
# Set the command-line arguments to pass to the server.
ARGS="--web.listen-address=:9100"
NODEEXP

# Ensure Node Exporter is running
systemctl enable prometheus-node-exporter
systemctl restart prometheus-node-exporter

# Verify Node Exporter is running
systemctl status prometheus-node-exporter

# Configureer hostname voor monitoring identificatie
echo "wp-server-$CONTAINER_NUM" > /etc/hostname
hostname -F /etc/hostname

echo "WordPress installation complete on container $CONTAINER_NUM"
EOF

# Vervang placeholders met echte waarden
sed -i "s/__SSH_USER__/$SSH_USER/g" /tmp/wp_install_${CONTAINER_ID}.sh
sed -i "s/__SSH_PASS__/$SSH_PASS/g" /tmp/wp_install_${CONTAINER_ID}.sh
sed -i "s/__DB_USER__/$DB_USER/g" /tmp/wp_install_${CONTAINER_ID}.sh
sed -i "s/__DB_PASS__/$DB_PASS/g" /tmp/wp_install_${CONTAINER_ID}.sh
sed -i "s/__ROOT_PASS__/$ROOT_PASS/g" /tmp/wp_install_${CONTAINER_ID}.sh
sed -i "s/__CONTAINER_NUM__/$CONTAINER_NUM/g" /tmp/wp_install_${CONTAINER_ID}.sh

# Kopieer en voer het script uit in de container
pct push $CONTAINER_ID /tmp/wp_install_${CONTAINER_ID}.sh /tmp/wp_install.sh
pct exec $CONTAINER_ID -- chmod +x /tmp/wp_install.sh
pct exec $CONTAINER_ID -- /tmp/wp_install.sh

# Haal de gegenereerde SSH key op voor latere toegang
mkdir -p ./ssh_keys
pct pull $CONTAINER_ID /root/ssh_keys/${SSH_USER}_key ./ssh_keys/${SSH_USER}_key
chmod 600 ./ssh_keys/${SSH_USER}_key

echo "Installation complete for container $CONTAINER_ID"
echo "SSH private key saved to ./ssh_keys/${SSH_USER}_key"

# Voeg container toe aan HA groep
ha-manager add ct:$CONTAINER_ID

# Maak monitoring directory aan als deze niet bestaat
mkdir -p /etc/prometheus/targets

# Voeg container info toe aan monitoring configuratie
echo "$IP_ADDRESS wp-lxc-$CONTAINER_NUM" >> /etc/prometheus/targets/wordpress_targets.yml

echo "Container $CONTAINER_ID added to HA and monitoring"