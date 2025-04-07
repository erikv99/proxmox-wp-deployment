# Proxmox WordPress Deployment

This repository contains scripts and Ansible playbooks for deploying WordPress in Proxmox environments for different customers.

## Repository Structure

- `customer1/` - Customer 1 deployment files
  - `ansible/` - Ansible playbooks and roles for automated deployment
  - `script_setup/` - Bash scripts for manual deployment
  
- `customer2/` - Customer 2 deployment files
  - `ansible/` - Ansible playbooks and roles for automated deployment
  - `script_setup/` - Bash scripts for manual deployment

## Quick Start

### Customer 1 (LXC containers)

```bash
# Setup using Bash scripts
./customer1_setup.sh

# Setup using Ansible
./customer1_setup.sh --ansible
# OR
./customer1_ansible_setup.sh

# Uninstall using Bash scripts
./customer1_uninstall.sh

# Uninstall using Ansible
./customer1_uninstall.sh --ansible
# OR
./customer1_ansible_uninstall.sh
```

### Customer 2 (VM-based)

```bash
# Setup using Bash scripts
./customer2_setup.sh

# Setup using Ansible
./customer2_setup.sh --ansible
# OR
./customer2_ansible_setup.sh

# Uninstall using Bash scripts
./customer2_uninstall.sh

# Uninstall using Ansible
./customer2_uninstall.sh --ansible
# OR
./customer2_ansible_uninstall.sh
```

For more details, see the README.md files in each customer directory.
