#!/bin/bash

CONTAINER_COUNT=2

apt install -y curl

# Eerste script uitvoeren om containers te maken
./customer1/c1_create_containers.sh

# Wacht even tot alle containers zijn opgestart
sleep 15

# Installeer WordPress op elke container
for ((i=0; i<CONTAINER_COUNT; i++)); do
   ID=$((100 + i))
   echo "Installing WordPress on container $ID"
   ./customer1/c1_install_wordpress_container.sh $ID
   
   # Wacht tussen installaties om overbelasting te voorkomen
   sleep 10
done

# Setup monitoring server configuration
mkdir -p /etc/prometheus
cat > /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'wordpress_servers'
    file_sd_configs:
      - files:
        - '/etc/prometheus/targets/wordpress_targets.yml'
EOF

# Check if Prometheus is installed, and if not, install it
if ! command -v prometheus &> /dev/null; then
  echo "Prometheus not found. Installing..."
  apt update
  apt install -y prometheus
fi

# Herstart monitoring service
systemctl restart prometheus || echo "Failed to restart Prometheus. Make sure it's installed properly."

echo "Setup complete for all WordPress containers"
echo "SSH keys zijn opgeslagen in ./ssh_keys/ directory"