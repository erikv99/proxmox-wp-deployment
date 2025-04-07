# Customer 1 WordPress Deployment

This directory contains deployment scripts for Customer 1's WordPress setup using LXC containers.

## Deployment Options

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x script_setup/*.sh

# For setup:
../customer1_setup.sh
# OR directly:
./script_setup/c1_setup.sh

# For removing/uninstalling:
../customer1_uninstall.sh
# OR directly:
./script_setup/c1_uninstall_containers.sh
```

### Using Ansible

```bash
# Setup
../customer1_ansible_setup.sh
# OR
cd ansible
ansible-playbook playbooks/wordpress.yml -e "ansible_action=setup"

# Uninstall
../customer1_ansible_uninstall.sh
# OR
cd ansible
ansible-playbook playbooks/wordpress.yml -e "ansible_action=uninstall"
```

## Configuration

Configuration settings are stored in:
- For bash scripts: Variables at the top of each script in script_setup/
- For Ansible: ansible/inventories/proxmox/group_vars/all.yml
