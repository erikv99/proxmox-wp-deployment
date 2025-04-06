#!/bin/bash

# Set up error handling
set -e
trap 'echo "Error on line $LINENO. Execution halted."' ERR

# Check if VM ID was provided
if [ -z "$1" ]; then
    echo "Usage: $0 <VM_ID> [VM_IP]"
    echo "Example: $0 150 10.24.30.100"
    exit 1
fi

VM_ID=$1
VM_IP=$2
STORAGE="ceph-pool"  # Default storage pool for RBD volumes

echo "Starting cleanup for VM $VM_ID..."

# Stop VM if running
if qm status $VM_ID &>/dev/null; then
    echo "VM $VM_ID exists. Stopping if running..."
    
    if qm status $VM_ID | grep -q running; then
        qm stop $VM_ID --timeout 180 || echo "Warning: Could not stop VM gracefully, forcing destruction"
        # Wait for VM to stop with timeout
        counter=0
        until ! qm status $VM_ID | grep -q running || [ $counter -ge 30 ]; do
            echo "Waiting for VM to stop... ($counter/30)"
            sleep 2
            ((counter++))
        done
        
        # If VM is still running after timeout, proceed anyway
        if qm status $VM_ID | grep -q running; then
            echo "Warning: VM still running after timeout. Will attempt destruction anyway."
        fi
    fi
    
    # Remove from HA if configured
    if command -v ha-manager &>/dev/null && ha-manager status 2>/dev/null | grep -q $VM_ID; then
        echo "Removing VM from HA configuration..."
        ha-manager remove vm:$VM_ID || echo "Warning: Could not remove VM from HA configuration"
    fi
    
    # Delete the VM
    echo "Destroying VM $VM_ID..."
    qm destroy $VM_ID --purge || {
        echo "Warning: Standard destruction failed, trying forced cleanup..."
        
        # Get disk information before destroying the VM configuration
        DISKS=$(qm config $VM_ID 2>/dev/null | grep -E 'scsi|virtio|ide|sata' | grep disk | awk '{print $1,$2}' || echo "")
        
        # Force destroy VM configuration
        qm destroy $VM_ID --skiplock || echo "Could not destroy VM configuration"
        
        # Manually clean up any leftover RBD volumes
        if [ ! -z "$DISKS" ]; then
            echo "Cleaning up potential leftover disk volumes..."
            for disk_info in $DISKS; do
                # Extract disk identifier
                if [[ $disk_info =~ ([a-z0-9]+): ]]; then
                    disk_id="vm-${VM_ID}-disk-${BASH_REMATCH[1]}"
                    echo "Checking for RBD volume: $disk_id"
                    
                    # Check if volume exists and remove it
                    if rbd -p $STORAGE ls 2>/dev/null | grep -q "$disk_id"; then
                        echo "Removing RBD volume: $disk_id"
                        rbd -p $STORAGE rm "$disk_id" || echo "Failed to remove RBD volume: $disk_id"
                    fi
                fi
            done
        fi
        
        # Check for additional numbered disks (0-9)
        for i in {0..9}; do
            disk_id="vm-${VM_ID}-disk-$i"
            if rbd -p $STORAGE ls 2>/dev/null | grep -q "$disk_id"; then
                echo "Removing RBD volume: $disk_id"
                rbd -p $STORAGE rm "$disk_id" || echo "Failed to remove RBD volume: $disk_id"
            fi
        done
    }
    
    echo "VM $VM_ID removed successfully."
else
    echo "VM $VM_ID does not exist in Proxmox configuration."
    
    # Still check for orphaned RBD volumes with this VM ID
    echo "Checking for orphaned RBD volumes..."
    for i in {0..9}; do
        disk_id="vm-${VM_ID}-disk-$i"
        if rbd -p $STORAGE ls 2>/dev/null | grep -q "$disk_id"; then
            echo "Found orphaned RBD volume: $disk_id"
            echo "Removing orphaned RBD volume..."
            rbd -p $STORAGE rm "$disk_id" || echo "Failed to remove RBD volume: $disk_id"
        fi
    done
fi

# Remove SSH host key if IP was provided
if [ ! -z "$VM_IP" ] && [ -f "/root/.ssh/known_hosts" ]; then
    echo "Removing SSH host key for $VM_IP..."
    ssh-keygen -f "/root/.ssh/known_hosts" -R "$VM_IP" 2>/dev/null || true
    echo "SSH host key removed."
fi

echo "Cleanup completed for VM $VM_ID."