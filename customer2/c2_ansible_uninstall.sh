#!/bin/bash

# Set up error handling
set -e
trap 'echo "Error on line $LINENO. Execution halted."' ERR

# Variables
ANSIBLE_DIR="$(dirname "$0")/ansible"

# Function for logging with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting WordPress VM uninstallation using Ansible"

# Check if ansible is installed
if ! command -v ansible &> /dev/null; then
    log "Ansible not found. Installing..."
    apt update
    apt install -y ansible
fi

# Make sure ansible directory exists
if [ ! -d "$ANSIBLE_DIR" ]; then
    log "Error: Ansible directory not found at $ANSIBLE_DIR"
    exit 1
fi

# Run the Ansible playbook with uninstall action
log "Running Ansible playbook for uninstallation"
cd "$ANSIBLE_DIR"
ansible-playbook playbooks/wordpress_vm.yml -e "ansible_action=uninstall"

log "Ansible playbook execution completed"
log "WordPress VM should now be uninstalled"