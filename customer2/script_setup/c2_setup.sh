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

# Clean up any existing VM and storage before proceeding
log "Cleaning up any existing VM with ID $VM_ID"
if [ -f "./customer2/script_setup/c2_remove_secure_vm.sh" ]; then
    bash ./customer2/script_setup/c2_remove_secure_vm.sh $VM_ID $VM_IP
    log "Cleanup completed"
else
    log "Warning: Cleanup script not found, may encounter issues if VM already exists"
fi

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

# Step 1: Create cloud-init configuration
source ./customer2/script_setup/c2_create_cloud_init.sh

# Step 2: VM setup and disk configuration
source ./customer2/script_setup/c2_setup_vm.sh

# Step 3: Wait for VM to be accessible
source ./customer2/script_setup/c2_wait_for_vm.sh

# Step 4: Install and configure WordPress
source ./customer2/script_setup/c2_install_wordpress.sh

log "Setup complete for WordPress VM"
log "SSH key saved to $SSH_KEY_DIR/${SSH_USER}_key"
log "WordPress is accessible at http://$VM_IP"
log "Credentials: "
log "  SSH: ssh -i \"$SSH_KEY_DIR/${SSH_USER}_key\" $SSH_USER@$VM_IP"
log "  WordPress database: wpuser/password123"
log "  WordPress admin: Complete the setup by visiting http://$VM_IP"

# Verify VM status one last time
qm status $VM_ID