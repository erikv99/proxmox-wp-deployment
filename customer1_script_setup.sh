#!/bin/bash
# Top-level setup script for Customer 1

echo "Starting Customer 1 WordPress deployment setup"

# Check if we should use Ansible or Bash scripts
if [ "$1" == "--ansible" ]; then
    echo "Using Ansible deployment method"
    cd customer1/ansible
    ansible-playbook playbooks/wordpress.yml -e "ansible_action=setup"
    cd ../..
else
    echo "Using Bash script deployment method"
    # Make sure scripts are executable
    chmod +x customer1/script_setup/*.sh
    # Run the setup script
    ./customer1/script_setup/c1_setup.sh
fi

echo "Customer 1 setup completed"
