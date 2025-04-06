#!/bin/bash

# Set up error handling
set -e
trap 'echo "Error on line $LINENO. Execution halted."' ERR

# Variables
VM_ID=150
VM_NAME="wp-secure-ha"
STORAGE="ceph-pool"
MEMORY=2048
CORES=2
BOOT_DISK_SIZE="50G"  # Explicitly set to 50GB
DATA_DISK_SIZE="50G"  # Also 50GB for data
BASE_IP="10.24.30"
VM_IP="${BASE_IP}.100"
SSH_USER="secure_user"
SSH_PASSWORD="password123"
CLOUD_CONFIG="/tmp/cloud-init-config.yml"

# Function for logging with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting WordPress VM setup script"

# Generate SSH key for later access
SSH_KEY_DIR="./ssh_keys"
mkdir -p $SSH_KEY_DIR
if [ ! -f "$SSH_KEY_DIR/${SSH_USER}_key" ]; then
    log "Generating SSH keys"
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_DIR/${SSH_USER}_key" -N ""
else
    log "SSH keys already exist, using existing keys"
fi

# Get the public key
SSH_PUBLIC_KEY=$(cat "$SSH_KEY_DIR/${SSH_USER}_key.pub")

# Create a cloud-init configuration with explicit disk resizing instructions
cat > $CLOUD_CONFIG << EOF
#cloud-config
hostname: wp-secure-ha
manage_etc_hosts: true
users:
  - name: $SSH_USER
    passwd: \$(openssl passwd -1 "$SSH_PASSWORD")
    groups: [sudo, adm]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh-authorized-keys:
      - $SSH_PUBLIC_KEY

# Basic packages
package_update: true
packages:
  - qemu-guest-agent
  - openssh-server
  - wget
  - curl
  - parted
  - e2fsprogs
  - cloud-utils
  - gdisk

# No automatic upgrades
package_upgrade: false

# Resize root and temp filesystems
growpart:
  mode: auto
  devices: ['/']
  ignore_growroot_disabled: false

resize_rootfs: true

bootcmd:
  - mount -o remount,size=1G /tmp
  - [ cloud-init-per, once, growroot-disk, growpart, /dev/sda, 1 ]
  - [ cloud-init-per, once, growroot-fs, resize2fs, /dev/sda1 ]

# Create disk setup script
write_files:
  - path: /usr/local/bin/setup-data-disk.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # Format the data disk if it's not already formatted
      if ! blkid /dev/sdb; then
        echo "Formatting data disk..."
        parted -s /dev/sdb mklabel gpt
        parted -s /dev/sdb mkpart primary ext4 0% 100%
        mkfs.ext4 /dev/sdb1
      fi
      
      # Create mount point
      mkdir -p /data
      
      # Add to fstab if not already there
      if ! grep -q "/data" /etc/fstab; then
        echo "/dev/sdb1 /data ext4 defaults 0 2" >> /etc/fstab
      fi
      
      # Mount the disk
      mount /data || true
      
      # Create directories for web content
      mkdir -p /data/www
      if [ ! -L /var/www ]; then
        # Save any existing content
        if [ -d /var/www ]; then
          cp -a /var/www/* /data/www/ 2>/dev/null || true
          rm -rf /var/www
        else
          mkdir -p /var/www
          rm -rf /var/www
        fi
        # Create symlink
        ln -sf /data/www /var/www
      fi
      
      # Set proper permissions
      chown -R www-data:www-data /data/www

  - path: /usr/local/bin/expand-root.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      echo "Expanding root partition and filesystem..."
      # Check current disk space
      df -h /
      
      # Ensure all available space is used
      growpart /dev/sda 1 || echo "Partition already using maximum space"
      resize2fs /dev/sda1
      
      # Check space after expansion
      echo "Disk space after expansion:"
      df -h /

# Run disk setup on first boot
runcmd:
  - 'bash /usr/local/bin/expand-root.sh'
  - 'bash /usr/local/bin/setup-data-disk.sh'
EOF

# Cleanup any existing VM with the same ID
log "Checking for existing VM with ID $VM_ID"
if qm status $VM_ID &>/dev/null; then
    log "VM with ID $VM_ID already exists. Stopping and removing it"
    qm stop $VM_ID --timeout 120 || true
    sleep 10
    qm destroy $VM_ID || true
    sleep 5
fi

# Download Ubuntu cloud image if you don't have it
UBUNTU_IMAGE="ubuntu-22.04-server-cloudimg-amd64.img"
UBUNTU_IMAGE_PATH="/var/lib/vz/template/iso/$UBUNTU_IMAGE"

if [ ! -f "$UBUNTU_IMAGE_PATH" ]; then
    log "Downloading Ubuntu cloud image..."
    wget -O $UBUNTU_IMAGE_PATH https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
else
    log "Using existing Ubuntu cloud image"
fi

log "Creating VM $VM_ID with Cloud-init..."
qm create $VM_ID --name $VM_NAME --memory $MEMORY --cores $CORES --net0 virtio,bridge=vmbr0

log "Importing boot disk"
qm importdisk $VM_ID $UBUNTU_IMAGE_PATH $STORAGE

log "Configuring VM storage - Setting boot disk to 50GB"
qm set $VM_ID --scsihw virtio-scsi-pci --scsi0 $STORAGE:vm-$VM_ID-disk-0,size=$BOOT_DISK_SIZE

# Manually create data disk RBD volume with explicit GB size
log "Creating RBD data volume"
rbd rm --no-progress ceph-pool/vm-$VM_ID-disk-1 2>/dev/null || true
rbd create --pool ceph-pool --size 50G vm-$VM_ID-disk-1

# Then attach it to the VM
log "Attaching data disk to VM"
qm set $VM_ID --scsi1 $STORAGE:vm-$VM_ID-disk-1

# Verify disk configuration
log "Checking if disks were properly configured"
qm config $VM_ID | grep scsi
log "If you don't see 50G sizes above, there's a problem with disk creation"

# Continue with rest of configuration
log "Configuring VM properties"
qm set $VM_ID --ide2 $STORAGE:cloudinit
qm set $VM_ID --boot c --bootdisk scsi0
qm set $VM_ID --serial0 socket --vga serial0
qm set $VM_ID --ipconfig0 ip=$VM_IP/24,gw=${BASE_IP}.1
qm set $VM_ID --agent enabled=1

# Save cloud-init config in Proxmox
log "Saving cloud-init configuration"
mkdir -p /var/lib/vz/snippets/
cp $CLOUD_CONFIG /var/lib/vz/snippets/cloud-init-config.yml
qm set $VM_ID --cicustom "user=local:snippets/cloud-init-config.yml"

# Start VM
log "Starting VM $VM_ID..."
qm start $VM_ID

# Wait for VM to be reachable
log "Waiting for VM to become accessible..."
MAX_PING_ATTEMPTS=40
PING_COUNT=0
while [ $PING_COUNT -lt $MAX_PING_ATTEMPTS ]; do
    if ping -c 1 -W 1 $VM_IP &>/dev/null; then
        log "VM is reachable via ping!"
        break
    fi
    log "Waiting for VM to boot... ($PING_COUNT/$MAX_PING_ATTEMPTS)"
    sleep 10
    PING_COUNT=$((PING_COUNT+1))
    
    # Check VM status
    if [ $((PING_COUNT % 3)) -eq 0 ]; then
        log "Checking VM status..."
        qm status $VM_ID
    fi
done

if [ $PING_COUNT -eq $MAX_PING_ATTEMPTS ]; then
    log "ERROR: VM did not become reachable within the timeout."
    log "Checking network configuration..."
    qm config $VM_ID
    exit 1
fi

log "Waiting for SSH service to start..."

# Wait for SSH with active polling
MAX_SSH_ATTEMPTS=30
SSH_COUNT=0
while [ $SSH_COUNT -lt $MAX_SSH_ATTEMPTS ]; do
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$SSH_KEY_DIR/${SSH_USER}_key" $SSH_USER@$VM_IP "echo SSH test" 2>/dev/null; then
        log "SSH is reachable!"
        break
    fi
    log "Waiting for SSH service... ($SSH_COUNT/$MAX_SSH_ATTEMPTS)"
    sleep 10
    SSH_COUNT=$((SSH_COUNT+1))
    
    if [ $SSH_COUNT -eq 5 ]; then
        log "Checking VM status during SSH wait..."
        qm status $VM_ID || true
    fi
done

if [ $SSH_COUNT -eq $MAX_SSH_ATTEMPTS ]; then
    log "ERROR: SSH did not become available within the timeout."
    log "Please check VM configuration manually."
    exit 1
fi

# Test SSH access and verify disk space
log "Testing SSH access and checking disk space..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_DIR/${SSH_USER}_key" $SSH_USER@$VM_IP << 'ENDSSH'
echo "SSH connection successful"
echo "Checking disk space:"
df -h
lsblk
echo "Checking mount points:"
mount | grep -E '^/dev/'
echo "Ensuring root partition is expanded:"
sudo bash /usr/local/bin/expand-root.sh
ENDSSH

# Install packages and set up WordPress via SSH in manageable batches
log "Installing packages and setting up WordPress via SSH..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_DIR/${SSH_USER}_key" $SSH_USER@$VM_IP << 'ENDSSH'
#!/bin/bash
set -e

echo "===== Starting WordPress setup ====="

# Check disk setup and ensure data disk is mounted
echo "Ensuring data disk is mounted..."
if ! df -h | grep -q "/data"; then
    echo "Running data disk setup script..."
    sudo bash /usr/local/bin/setup-data-disk.sh
    df -h
fi

# Create a larger /tmp directory to prevent installation issues
echo "Ensuring /tmp has sufficient space..."
sudo mount -o remount,size=2G /tmp
df -h /tmp

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

# Install each package group with checks
echo "Installing Apache server..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apache2
df -h

echo "Installing PHP base..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y php libapache2-mod-php
df -h

echo "Installing PHP database modules..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y php-mysql
df -h

echo "Installing PHP extensions (part 1)..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y php-curl php-gd
df -h

echo "Installing PHP extensions (part 2)..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y php-mbstring php-xml
df -h

echo "Installing PHP extensions (part 3)..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y php-xmlrpc php-soap php-intl php-zip
df -h

echo "Installing MySQL client..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-client
df -h

# Install MySQL server in smaller chunks to avoid memory issues
echo "Installing MySQL server components separately..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mysql-common
df -h

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mysql-server-core-8.0
df -h

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mysql-server
df -h

# Alternative: Try MariaDB if MySQL installation fails
if ! command -v mysql &>/dev/null; then
    echo "MySQL installation failed, trying MariaDB instead..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server
fi

echo "Final disk space after all installations:"
df -h

# Configure MySQL/MariaDB database
if command -v mysql >/dev/null 2>&1; then
    echo "Database server is installed, configuring database..."
    
    # Start database service if not running
    if ! sudo systemctl is-active mysql &>/dev/null && ! sudo systemctl is-active mariadb &>/dev/null; then
        if [ -f /lib/systemd/system/mysql.service ]; then
            sudo systemctl start mysql
            sudo systemctl enable mysql
        elif [ -f /lib/systemd/system/mariadb.service ]; then
            sudo systemctl start mariadb
            sudo systemctl enable mariadb
        fi
    fi
    
    # Configure database
    echo "Creating database and user..."
    sudo mysql -e "CREATE DATABASE IF NOT EXISTS wordpress;"
    sudo mysql -e "CREATE USER IF NOT EXISTS 'wpuser'@'localhost' IDENTIFIED BY 'password123';"
    sudo mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';"
    sudo mysql -e "FLUSH PRIVILEGES;"
else
    echo "ERROR: Database server installation failed!"
fi

# Download and install WordPress
echo "Downloading WordPress..."
cd /tmp
sudo wget -c https://wordpress.org/latest.tar.gz
sudo tar -xzf latest.tar.gz
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
echo "y" | sudo ufw enable

# Final status
echo "===== Installation Complete ====="
echo "Disk usage:"
df -h
echo "Apache status:"
sudo systemctl status apache2 --no-pager
echo "Database status:"
if [ -f /lib/systemd/system/mysql.service ]; then
    sudo systemctl status mysql --no-pager
elif [ -f /lib/systemd/system/mariadb.service ]; then
    sudo systemctl status mariadb --no-pager
fi
echo "WordPress installation directory:"
ls -la /var/www/html/
ENDSSH

# Check for successful installation
log "Checking if Apache is running on the VM..."
if ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_DIR/${SSH_USER}_key" $SSH_USER@$VM_IP "systemctl is-active apache2" &>/dev/null; then
    log "Apache is running. WordPress setup complete."
else
    log "WARNING: Apache is not running. Setup might not be complete."
fi

# Test if the WordPress site is accessible
log "Testing HTTP connectivity to WordPress..."
for i in {1..5}; do
    if curl -I --connect-timeout 5 http://$VM_IP &>/dev/null; then
        log "WordPress is now accessible via HTTP!"
        break
    fi
    log "WordPress not yet accessible via HTTP, waiting... (attempt $i/5)"
    sleep 10
done

log "Setup complete for WordPress VM"
log "SSH key saved to $SSH_KEY_DIR/${SSH_USER}_key"
log "WordPress is accessible at http://$VM_IP"
log "Credentials: "
log "  SSH: ssh -i \"$SSH_KEY_DIR/${SSH_USER}_key\" $SSH_USER@$VM_IP"
log "  WordPress database: wpuser/password123"
log "  WordPress admin: Complete the setup by visiting http://$VM_IP"

# Verify VM status one last time
qm status $VM_ID