## Bash setup

# After updating the .sh files
chmod +x customer1/*.sh

# For setup:
./customer1/c1_setup.sh

# For removing on retry (dev purposes):
./customer1/c1_uninstall_containers.sh

## Ansible setup

# Setup
ansible-playbook playbooks/wordpress_vm.yml -e "ansible_action=setup"

# Uninstall
ansible-playbook playbooks/wordpress_vm.yml -e "ansible_action=uninstall"