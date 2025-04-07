## Bash setup

# After updating the .sh files
chmod +x customer2/*.sh

# For setup:
./customer2/c2_setup.sh

# For removing on retry (dev purposes):
./customer2/c2_uninstall_VM.sh 150 10.24.30.100

## Ansible setup

# Setup
ansible-playbook playbooks/wordpress_vm.yml -e "ansible_action=setup"

# Uninstall
ansible-playbook playbooks/wordpress_vm.yml -e "ansible_action=uninstall"
