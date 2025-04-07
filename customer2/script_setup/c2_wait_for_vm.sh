#!/bin/bash

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
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$SSH_KEY_DIR/${SSH_USER}_key" $SSH_USER@$VM_IP << 'ENDSSH'
echo "SSH connection successful"
echo "Checking disk space:"
df -h
echo "Block devices:"
lsblk
echo "Checking mount points:"
mount | grep -E '^/dev/'
ENDSSH