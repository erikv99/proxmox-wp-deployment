#!/bin/bash
# Top-level uninstall script for Customer 1

echo "Starting Customer 1 WordPress deployment uninstall"

# Check if we should use Ansible or Bash scripts
if [ "$1" == "--ansible" ]; then
    echo "Using Ansible uninstall method"
    cd customer1/ansible
    ansible-playbook playbooks/wordpress.yml -e "ansible_action=uninstall"
    cd ../..
else
    echo "Using Bash script uninstall method"
    # Make sure scripts are executable
    chmod +x customer1/script_setup/*.sh
    # Run the uninstall script
    ./customer1/script_setup/c1_uninstall_containers.sh
fi

echo "Customer 1 uninstall completed"
