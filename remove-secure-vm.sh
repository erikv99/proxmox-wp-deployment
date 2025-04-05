#!/bin/bash

# Check if VM ID was provided
if [ -z "$1" ]; then
    echo "Usage: $0 <VM_ID> [VM_IP]"
    echo "Example: $0 150 10.24.30.100"
    exit 1
fi

VM_ID=$1
VM_IP=$2

echo "Starting cleanup for VM $VM_ID..."

# Stop VM if running
if qm status $VM_ID &>/dev/null; then
    echo "VM $VM_ID exists. Stopping if running..."
    
    if qm status $VM_ID | grep -q running; then
        qm stop $VM_ID
        # Wait for VM to stop
        until ! qm status $VM_ID | grep -q running; do
            echo "Waiting for VM to stop..."
            sleep 2
        done
    fi
    
    # Remove from HA if configured
    if command -v ha-manager &>/dev/null && ha-manager status 2>/dev/null | grep -q $VM_ID; then
        echo "Removing VM from HA configuration..."
        ha-manager remove vm:$VM_ID
    fi
    
    # Delete the VM
    echo "Destroying VM $VM_ID..."
    qm destroy $VM_ID --purge
    
    echo "VM $VM_ID removed successfully."
else
    echo "VM $VM_ID does not exist, nothing to remove."
fi

# Remove SSH host key if IP was provided
if [ ! -z "$VM_IP" ] && [ -f "/root/.ssh/known_hosts" ]; then
    echo "Removing SSH host key for $VM_IP..."
    ssh-keygen -f "/root/.ssh/known_hosts" -R "$VM_IP" 2>/dev/null || true
    echo "SSH host key removed."
fi

echo "Cleanup completed for VM $VM_ID."