#!/bin/bash

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

# Prepare the boot disk using standard Proxmox commands
log "Importing and resizing boot disk to 50GB"
qm importdisk $VM_ID $UBUNTU_IMAGE_PATH $STORAGE
qm set $VM_ID --scsihw virtio-scsi-pci --scsi0 $STORAGE:vm-$VM_ID-disk-0
qm resize $VM_ID scsi0 50G

# Create and attach data disk
log "Creating data disk RBD volume"
rbd rm --no-progress ceph-pool/vm-$VM_ID-disk-1 2>/dev/null || true
rbd create --pool ceph-pool --size 50G vm-$VM_ID-disk-1

log "Attaching data disk to VM"
qm set $VM_ID --scsi1 $STORAGE:vm-$VM_ID-disk-1

# Verify disk configuration
log "Checking if disks were properly configured"
qm config $VM_ID | grep scsi
log "If you don't see 50G sizes for both disks, there's a problem with disk creation"

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

log "Adding VM to HA configuration..."
ha-manager add vm:$VM_ID || echo "Warning: Could not add VM to HA configuration"