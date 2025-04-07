#!/bin/bash
# Top-level uninstall script for Customer 2

echo "Starting Customer 2 WordPress deployment uninstall"

# Check if we should use Ansible or Bash scripts
if [ "$1" == "--ansible" ]; then
    echo "Using Ansible uninstall method"
    # Use the existing ansible uninstall script
    ./customer2/script_setup/c2_ansible_uninstall.sh
else
    echo "Using Bash script uninstall method"
    # Make sure scripts are executable
    chmod +x customer2/script_setup/*.sh
    # Check if we have arguments for VM ID and IP
    if [ -n "$2" ] && [ -n "$3" ]; then
        # Run the uninstall script with provided VM ID and IP
        ./customer2/script_setup/c2_uninstall_vm.sh $2 $3
    else
        # Run with default values
        ./customer2/script_setup/c2_uninstall_vm.sh 150 10.24.30.100
    fi
fi

echo "Customer 2 uninstall completed"
