#!/bin/bash

# Variabelen
VM_ID=150
VM_NAME="wp-secure-ha"
STORAGE="ceph-pool"
MEMORY=2048
CORES=2
DISK_SIZE="50G"
BASE_IP="10.24.30"
VM_IP="${BASE_IP}.100"
SSH_USER="secure_user"
SSH_PASSWORD="password"  # Dit wordt alleen bij initiële setup gebruikt
CLOUD_CONFIG="/tmp/cloud-init-config.yml"

# Genereer SSH key voor latere toegang
SSH_KEY_DIR="./ssh_keys"
mkdir -p $SSH_KEY_DIR
ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_DIR/${SSH_USER}_key" -N "" -y

# Haal de publieke sleutel op
SSH_PUBLIC_KEY=$(cat "$SSH_KEY_DIR/${SSH_USER}_key.pub")

# Cloud-init configuratie maken
cat > $CLOUD_CONFIG << EOF
#cloud-config
hostname: wp-secure-ha
manage_etc_hosts: true
users:
  - name: $SSH_USER
    passwd: \$(openssl passwd -1 "$SSH_PASSWORD")
    groups: [sudo]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh-authorized-keys:
      - $SSH_PUBLIC_KEY
package_update: true
package_upgrade: true
packages:
  - apache2
  - mariadb-server
  - php
  - libapache2-mod-php
  - php-mysql
  - php-curl
  - php-gd
  - php-mbstring
  - php-xml
  - php-xmlrpc
  - php-soap
  - php-intl
  - php-zip
  - ufw
  - prometheus-node-exporter
runcmd:
  # Configureer firewall
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 22/tcp
  - ufw allow 80/tcp
  - ufw allow 443/tcp
  - ufw allow 9100/tcp
  - echo "y" | ufw enable
  
  # Configureer database
  - mysql -e "CREATE DATABASE wordpress;"
  - mysql -e "CREATE USER 'wpuser'@'localhost' IDENTIFIED BY 'password123';"
  - mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';"
  - mysql -e "FLUSH PRIVILEGES;"
  
  # Download en installeer WordPress
  - cd /var/www/html
  - rm index.html
  - wget https://wordpress.org/latest.tar.gz
  - tar -xzf latest.tar.gz
  - cp -r wordpress/* .
  - rm -rf wordpress latest.tar.gz
  - cp wp-config-sample.php wp-config.php
  - sed -i "s/database_name_here/wordpress/" wp-config.php
  - sed -i "s/username_here/wpuser/" wp-config.php
  - sed -i "s/password_here/password123/" wp-config.php
  - chown -R www-data:www-data /var/www/html/
  
  # Genereer unieke beveiligingssleutels
  - WP_KEYS=\$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
  - sed -i "/define( 'AUTH_KEY'/,/define( 'NONCE_SALT'/d" wp-config.php
  - sed -i "/put your unique phrase here/d" wp-config.php
  - sed -i "/That's all, stop editing/i \$(echo \$WP_KEYS | sed 's/"/\\"/g')" wp-config.php
  
  # Start monitoring service
  - systemctl enable prometheus-node-exporter
  - systemctl start prometheus-node-exporter
EOF

# Download Ubuntu cloud image als je die nog niet hebt
UBUNTU_IMAGE="ubuntu-22.04-server-cloudimg-amd64.img"
UBUNTU_IMAGE_PATH="/var/lib/vz/template/iso/$UBUNTU_IMAGE"

if [ ! -f "$UBUNTU_IMAGE_PATH" ]; then
    echo "Downloading Ubuntu cloud image..."
    wget -O $UBUNTU_IMAGE_PATH https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
fi

# VM aanmaken met Cloud-init
echo "Creating VM $VM_ID with Cloud-init..."
qm create $VM_ID --name $VM_NAME --memory $MEMORY --cores $CORES --net0 virtio,bridge=vmbr0
qm importdisk $VM_ID $UBUNTU_IMAGE_PATH $STORAGE
qm set $VM_ID --scsihw virtio-scsi-pci --scsi0 $STORAGE:vm-$VM_ID-disk-0
qm set $VM_ID --ide2 $STORAGE:cloudinit
qm set $VM_ID --boot c --bootdisk scsi0
qm set $VM_ID --serial0 socket --vga serial0
qm set $VM_ID --ipconfig0 ip=$VM_IP/24,gw=${BASE_IP}.1
qm set $VM_ID --cicustom "user=local:snippets/cloud-init-config.yml"

# Cloud-init config opslaan in Proxmox
mkdir -p /var/lib/vz/snippets/
cp $CLOUD_CONFIG /var/lib/vz/snippets/cloud-init-config.yml

# Start VM
echo "Starting VM $VM_ID..."
qm start $VM_ID

# Wacht tot VM bereikbaar is
echo "Waiting for VM to become accessible..."
until ping -c 1 $VM_IP &>/dev/null; do
    echo "Waiting for VM to boot..."
    sleep 5
done

echo "Waiting for SSH service to start..."
sleep 15

# Test SSH toegang
echo "Testing SSH access..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_DIR/${SSH_USER}_key" $SSH_USER@$VM_IP "echo SSH connection successful"

# Configureer HA
echo "Setting up High Availability for VM $VM_ID..."
ha-manager add vm:$VM_ID

# Voeg toe aan monitoring
echo "Adding to monitoring configuration..."
mkdir -p /etc/prometheus/targets
echo "$VM_IP $VM_NAME" >> /etc/prometheus/targets/secure_wordpress_targets.yml

echo "Setup complete for WordPress VM with HA"
echo "SSH key saved to $SSH_KEY_DIR/${SSH_USER}_key"
echo "WordPress is accessible at http://$VM_IP"