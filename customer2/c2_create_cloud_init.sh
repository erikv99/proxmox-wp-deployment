#!/bin/bash

log "Creating cloud-init configuration..."

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

# Create disk setup script
write_files:
  - path: /usr/local/bin/setup-data-disk.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      echo "Starting data disk setup script..."
      echo "Current block devices:"
      lsblk
      
      # Wait for the data disk to appear
      MAX_WAIT=60
      WAIT_COUNT=0
      
      while [ ! -e /dev/sdb ] && [ $WAIT_COUNT -lt $MAX_WAIT ]; do
        echo "Waiting for /dev/sdb to appear... ($WAIT_COUNT/$MAX_WAIT)"
        sleep 2
        WAIT_COUNT=$((WAIT_COUNT+1))
      done
      
      if [ ! -e /dev/sdb ]; then
        echo "ERROR: Data disk /dev/sdb did not appear after waiting"
        exit 1
      fi
      
      echo "Data disk /dev/sdb found. Creating partition..."
      
      # Format the data disk if it's not already formatted
      if ! blkid /dev/sdb; then
        echo "Formatting data disk..."
        parted -s /dev/sdb mklabel gpt
        parted -s /dev/sdb mkpart primary ext4 0% 100%
        sleep 2  # Give the system time to register the new partition
      fi
      
      # Wait for the new partition to appear
      WAIT_COUNT=0
      while [ ! -e /dev/sdb1 ] && [ $WAIT_COUNT -lt $MAX_WAIT ]; do
        echo "Waiting for /dev/sdb1 to appear... ($WAIT_COUNT/$MAX_WAIT)"
        sleep 2
        WAIT_COUNT=$((WAIT_COUNT+1))
      done
      
      if [ ! -e /dev/sdb1 ]; then
        echo "ERROR: Partition /dev/sdb1 did not appear after creation"
        exit 1
      fi
      
      echo "Creating filesystem on /dev/sdb1..."
      mkfs.ext4 /dev/sdb1
      
      # Create mount point
      mkdir -p /data
      
      # Add to fstab if not already there
      if ! grep -q "/data" /etc/fstab; then
        echo "/dev/sdb1 /data ext4 defaults 0 2" >> /etc/fstab
      fi
      
      # Mount the disk
      echo "Mounting /dev/sdb1 to /data..."
      mount /data
      
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
      
      echo "Data disk setup complete:"
      df -h /data

  - path: /usr/local/bin/expand-root.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      echo "Checking root filesystem..."
      df -h /
      
      # Make sure growpart is available
      if ! command -v growpart &> /dev/null; then
          apt-get update
          apt-get install -y cloud-guest-utils
      fi
      
      echo "Expanding root partition and filesystem..."
      growpart /dev/sda 1 || echo "Partition may already be using maximum space"
      sleep 2
      resize2fs /dev/sda1
      
      echo "Root filesystem after expansion:"
      df -h /

# Run disk setup on first boot
runcmd:
  - 'echo "Running first boot commands..."'
  - 'bash /usr/local/bin/expand-root.sh'
  - 'bash /usr/local/bin/setup-data-disk.sh'
EOF

log "Cloud-init configuration created"