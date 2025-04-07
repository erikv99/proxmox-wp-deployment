#!/bin/bash
# Direct Ansible uninstall for Customer 2

echo "Starting Customer 2 Ansible uninstallation"
cd customer2/ansible
ansible-playbook playbooks/wordpress_vm.yml -e "ansible_action=uninstall"
cd ../..
echo "Customer 2 Ansible uninstallation completed"
