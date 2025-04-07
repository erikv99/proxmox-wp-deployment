#!/bin/bash
# Direct Ansible uninstall for Customer 1

echo "Starting Customer 1 Ansible uninstallation"
cd customer1/ansible
ansible-playbook playbooks/wordpress.yml -e "ansible_action=uninstall"
cd ../..
echo "Customer 1 Ansible uninstallation completed"
