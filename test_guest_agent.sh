#!/bin/bash
# filepath: /root/proxmox-wp-deployment/test_guest_agent.sh

VM_ID=150
VM_IP="10.24.30.100"
SSH_USER="secure_user"
SSH_KEY_DIR="./ssh_keys"

# Function for logging with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting guest agent tests for VM $VM_ID..."

# Check if guest agent is enabled in VM configuration
log "Checking if guest agent is enabled in VM configuration:"
if qm config $VM_ID | grep -q "agent.*enabled=1"; then
    log "✅ Guest agent is enabled in VM configuration"
else
    log "❌ Guest agent is NOT enabled in VM configuration"
    log "Enabling guest agent..."
    qm set $VM_ID --agent enabled=1
fi

# Check if we can SSH to VM
log "Testing SSH connectivity to VM..."
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$SSH_KEY_DIR/${SSH_USER}_key" $SSH_USER@$VM_IP "echo SSH test" &>/dev/null; then
    log "✅ SSH connection successful"
    
    # Check if qemu-guest-agent is installed in VM
    log "Checking if qemu-guest-agent is installed in VM..."
    if ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_DIR/${SSH_USER}_key" $SSH_USER@$VM_IP "dpkg -l qemu-guest-agent" | grep -q "ii"; then
        log "✅ qemu-guest-agent is installed"
    else
        log "❌ qemu-guest-agent is NOT installed"
        log "Installing qemu-guest-agent..."
        ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_DIR/${SSH_USER}_key" $SSH_USER@$VM_IP "sudo apt-get update && sudo apt-get install -y qemu-guest-agent"
    fi
    
    # Check if qemu-guest-agent service is running
    log "Checking if qemu-guest-agent service is running..."
    if ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_DIR/${SSH_USER}_key" $SSH_USER@$VM_IP "sudo systemctl is-active qemu-guest-agent" &>/dev/null; then
        log "✅ qemu-guest-agent service is running"
    else
        log "❌ qemu-guest-agent service is NOT running"
        log "Starting qemu-guest-agent service..."
        ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_DIR/${SSH_USER}_key" $SSH_USER@$VM_IP "sudo systemctl start qemu-guest-agent && sudo systemctl enable qemu-guest-agent"
    fi
else
    log "❌ SSH connection failed"
fi

# Test agent functionality through Proxmox
log "Testing guest agent functionality through Proxmox..."
log "Pinging guest agent..."
if qm agent $VM_ID ping &>/dev/null; then
    log "✅ Guest agent ping successful"
    
    log "Getting guest information:"
    qm agent $VM_ID info
    
    log "Getting guest network interfaces:"
    qm agent $VM_ID network-get-interfaces
    
    log "Getting guest filesystem information:"
    qm agent $VM_ID get-fsinfo
    
    log "Getting guest time:"
    qm agent $VM_ID get-time
    
    log "ALL TESTS PASSED: Guest agent is properly configured and working!"
else
    log "❌ Guest agent ping failed"
    log "Troubleshooting actions:"
    log "1. Ensure VM is fully booted"
    log "2. Verify qemu-guest-agent is installed and running in VM"
    log "3. Restart the qemu-guest-agent service inside VM"
    log "4. Restart the VM"
fi

log "Guest agent test completed."