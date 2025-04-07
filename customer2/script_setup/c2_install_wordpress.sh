#!/bin/bash

# Install packages and set up WordPress via SSH in manageable batches
log "Installing packages and setting up WordPress via SSH..."

# SSH session to install WordPress and dependencies
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$SSH_KEY_DIR/${SSH_USER}_key" $SSH_USER@$VM_IP << 'ENDSSH'
#!/bin/bash
set -e

echo "===== Starting WordPress setup ====="
# Get the real IP address of this VM from the system
VM_IP=$(hostname -I | awk '{print $1}')
echo "Using VM IP: $VM_IP"

# Check disk setup and ensure data disk is mounted
echo "Ensuring data disk is mounted..."
if ! df -h | grep -q "/data"; then
    echo "Running data disk setup script..."
    sudo bash /usr/local/bin/setup-data-disk.sh
fi

# Create a temporary directory on the root filesystem
echo "Setting up temporary directory..."
TEMP_DIR="/tmp_install"
sudo mkdir -p $TEMP_DIR
sudo chmod 1777 $TEMP_DIR

# Set temporary directory variables
export TMPDIR="$TEMP_DIR"
export TMP="$TEMP_DIR"
export TEMP="$TEMP_DIR"

echo "Checking disk space before installation:"
df -h

# Wait for apt to be available
echo "Waiting for apt to be available..."
APT_ATTEMPTS=0
while [ $APT_ATTEMPTS -lt 30 ]; do
    if ! ps aux | grep -v grep | grep -q 'apt-get'; then
        echo "Apt is available now"
        break
    fi
    echo "Apt is locked by another process... waiting (attempt $APT_ATTEMPTS/30)"
    sleep 10
    APT_ATTEMPTS=$((APT_ATTEMPTS+1))
done

# Clean apt 
echo "Cleaning apt caches..."
sudo apt-get clean
echo "Disk space before updates:"
df -h

# Update package lists
echo "Updating package repositories..."
sudo apt-get update

# Install Apache and monitor disk space
echo "Installing Apache server..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apache2
df -h

# Install PHP components in small batches
echo "Installing PHP and its components..."
for pkg in php libapache2-mod-php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip; do
    echo "Installing $pkg..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $pkg
    sleep 1  # Short pause between installations
done
df -h

# Install MariaDB instead of MySQL (more reliable)
echo "Installing MariaDB database server..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mariadb-server
df -h

# Check MariaDB status - removed redundant installation
echo "Checking MariaDB status..."
sudo systemctl status mariadb --no-pager || true

echo "Final disk space after all installations:"
df -h

# Configure MariaDB database
echo "Configuring database..."
if sudo systemctl is-active mariadb &>/dev/null || sudo systemctl is-active mysql &>/dev/null; then
    echo "Database server is running, creating WordPress database..."
    
    # Create database and user
    sudo mysql -e "CREATE DATABASE IF NOT EXISTS wordpress;"
    sudo mysql -e "CREATE USER IF NOT EXISTS 'wpuser'@'localhost' IDENTIFIED BY 'password123';"
    sudo mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';"
    sudo mysql -e "FLUSH PRIVILEGES;"
else
    echo "ERROR: Database server is not running! Attempting to start..."
    sudo systemctl start mariadb
    sleep 5
    
    if sudo systemctl is-active mariadb &>/dev/null; then
        echo "MariaDB started successfully, creating database..."
        sudo mysql -e "CREATE DATABASE IF NOT EXISTS wordpress;"
        sudo mysql -e "CREATE USER IF NOT EXISTS 'wpuser'@'localhost' IDENTIFIED BY 'password123';"
        sudo mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';"
        sudo mysql -e "FLUSH PRIVILEGES;"
    else
        echo "CRITICAL: Could not start MariaDB, installation may fail"
        sudo systemctl status mariadb --no-pager || true
    fi
fi

# Download and install WordPress
echo "Downloading WordPress..."
cd "$TEMP_DIR"
sudo wget -c https://wordpress.org/latest.tar.gz
sudo tar -xzf latest.tar.gz

# Make sure /var/www/html exists and is accessible
sudo mkdir -p /var/www/html
if [ -L /var/www ]; then
    echo "/var/www is a symlink to $(readlink /var/www)"
    # Make sure the target exists
    sudo mkdir -p $(readlink /var/www)
fi

# Copy WordPress files
echo "Copying WordPress files to web directory..."
sudo cp -r wordpress/* /var/www/html/
sudo rm -rf wordpress latest.tar.gz

# Configure WordPress
echo "Creating wp-config.php..."
cd /var/www/html
if [ -f wp-config-sample.php ]; then
    sudo cp wp-config-sample.php wp-config.php
    sudo sed -i "s/database_name_here/wordpress/" wp-config.php
    sudo sed -i "s/username_here/wpuser/" wp-config.php
    sudo sed -i "s/password_here/password123/" wp-config.php
    
    # Generate security keys
    echo "Generating security keys..."
    WP_KEYS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
    if [ -n "$WP_KEYS" ]; then
        sudo sed -i "/define( 'AUTH_KEY'/,/define( 'NONCE_SALT'/d" wp-config.php
        sudo sed -i "/put your unique phrase here/d" wp-config.php
        echo "$WP_KEYS" | sudo tee -a wp-config.php > /dev/null
    fi
    
    # Add WordPress security hardening
    echo "Adding security configuration to wp-config.php..."
    sudo bash -c "cat >> /var/www/html/wp-config.php << 'EOL'

/* Security hardening */
define('DISALLOW_FILE_EDIT', true);
define('DISALLOW_FILE_MODS', true);
define('FORCE_SSL_ADMIN', true);
define('WP_AUTO_UPDATE_CORE', true);
EOL"
else
    echo "ERROR: WordPress files not extracted correctly"
fi

# Set permissions
echo "Setting permissions..."
sudo chown -R www-data:www-data /var/www/html/
sudo chmod -R 755 /var/www/html/

# Configure firewall
echo "Configuring firewall..."
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
echo "y" | sudo ufw enable || true  # Allow this to fail if already enabled

# Install SSL using self-signed certificate
echo "Setting up HTTPS with self-signed certificate..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ssl-cert

# Generate a self-signed certificate
echo "Generating self-signed certificate..."
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/apache-selfsigned.key \
  -out /etc/ssl/certs/apache-selfsigned.crt \
  -subj "/CN=${VM_IP}"

# Create Apache SSL configuration
echo "Configuring Apache for SSL..."
sudo bash -c "cat > /etc/apache2/sites-available/wordpress-ssl.conf << EOL
<VirtualHost *:80>
    ServerName ${VM_IP}
    DocumentRoot /var/www/html
    
    <Directory /var/www/html>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerName ${VM_IP}
    DocumentRoot /var/www/html
    
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/apache-selfsigned.crt
    SSLCertificateKeyFile /etc/ssl/private/apache-selfsigned.key
    
    <Directory /var/www/html>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOL"

# Enable required modules and site
echo "Enabling Apache SSL configuration..."
sudo a2enmod ssl
sudo a2ensite wordpress-ssl.conf
sudo a2enmod rewrite

# Restart Apache to apply changes
sudo systemctl restart apache2

echo "Self-signed SSL certificate installed successfully"
echo "Note: Browsers will show a security warning for self-signed certificates"
echo "Your site is accessible via HTTPS at https://${VM_IP}"

# Cleanup temporary directory
sudo rm -rf "$TEMP_DIR"

# Final status
echo "===== Installation Complete ====="
echo "Disk usage:"
df -h
echo "Apache status:"
sudo systemctl status apache2 --no-pager
ENDSSH

# Check for successful installation
log "Checking if Apache is running on the VM..."
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$SSH_KEY_DIR/${SSH_USER}_key" $SSH_USER@$VM_IP "systemctl is-active apache2" &>/dev/null; then
    log "Apache is running. WordPress setup complete."
else
    log "WARNING: Apache is not running. Setup might not be complete."
fi

# Test if the WordPress site is accessible
log "Testing HTTP connectivity to WordPress..."
for i in {1..10}; do
    if curl -I --connect-timeout 5 http://$VM_IP &>/dev/null; then
        log "WordPress is now accessible via HTTP!"
        break
    fi
    log "WordPress not yet accessible via HTTP, waiting... (attempt $i/10)"
    sleep 10
done

log "WordPress is also accessible via HTTPS at https://$VM_IP (with self-signed certificate warning)"
log "WordPress installation completed"