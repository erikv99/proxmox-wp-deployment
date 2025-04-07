#!/bin/bash
# Top-level setup script for Customer 2

echo "Starting Customer 2 WordPress deployment setup"

# Check if we should use Ansible or Bash scripts
if [ "$1" == "--ansible" ]; then
    echo "Using Ansible deployment method"
    # Use the existing ansible setup script
    ./customer2/script_setup/c2_ansible_setup.sh
else
    echo "Using Bash script deployment method"
    # Make sure scripts are executable
    chmod +x customer2/script_setup/*.sh
    # Run the setup script
    ./customer2/script_setup/c2_setup.sh
fi

echo "Customer 2 setup completed"
