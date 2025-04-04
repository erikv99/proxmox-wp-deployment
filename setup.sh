#!/bin/bash

CONTAINER_COUNT = 1

apt install -y curl

# Eerste script uitvoeren om containers te maken
./create_containers.sh

# Wacht even tot alle containers zijn opgestart
sleep 15

# Installeer WordPress op elke container
for ((i=0; i<CONTAINER_COUNT; i++)); do
   ID=$((100 + i))
   echo "Installing WordPress on container $ID"
   ./install_wordpress_container.sh $ID
   
   # Wacht tussen installaties om overbelasting te voorkomen
   sleep 10
done

# Setup monitoring server configuration
cat > /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'wordpress_servers'
    file_sd_configs:
      - files:
        - '/etc/prometheus/targets/wordpress_targets.yml'
EOF

# Herstart monitoring service
systemctl restart prometheus

echo "Setup complete for all WordPress containers"
echo "SSH keys zijn opgeslagen in ./ssh_keys/ directory"