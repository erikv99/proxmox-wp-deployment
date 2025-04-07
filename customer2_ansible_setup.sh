#!/bin/bash
# Direct Ansible setup for Customer 2

echo "Starting Customer 2 Ansible deployment"
cd customer2/ansible
ansible-playbook playbooks/wordpress_vm.yml -e "ansible_action=setup"
cd ../..
echo "Customer 2 Ansible setup completed"
