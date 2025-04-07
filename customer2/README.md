# Customer 2 WordPress Deployment

This directory contains deployment scripts for Customer 2's WordPress setup using Proxmox VMs.

## Deployment Options

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x script_setup/*.sh

# For setup:
../customer2_setup.sh
# OR directly:
./script_setup/c2_setup.sh

# For removing/uninstalling:
../customer2_uninstall.sh
# OR directly:
./script_setup/c2_uninstall_vm.sh 150 10.24.30.100
```

### Using Ansible

```bash
# Setup
../customer2_ansible_setup.sh
# OR
cd ansible
ansible-playbook playbooks/wordpress_vm.yml -e "ansible_action=setup"

# Uninstall
../customer2_ansible_uninstall.sh
# OR
cd ansible
ansible-playbook playbooks/wordpress_vm.yml -e "ansible_action=uninstall"
```

## Configuration

Configuration settings are stored in:
- For bash scripts: Variables at the top of each script in script_setup/
- For Ansible: ansible/inventories/proxmox/group_vars/all.yml
