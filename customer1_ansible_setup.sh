#!/bin/bash
# Direct Ansible setup for Customer 1

echo "Starting Customer 1 Ansible deployment"
cd customer1/ansible
ansible-playbook playbooks/wordpress.yml -e "ansible_action=setup"
cd ../..
echo "Customer 1 Ansible setup completed"
