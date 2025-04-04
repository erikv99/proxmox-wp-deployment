#!/bin/bash

# Variabelen voor container configuratie
BASE_IP="10.24.30" 
START_ID=100        
COUNT=3             
STORAGE="ceph-pool"
TEMPLATE="local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"

# Loop om containers te maken
for ((i=0; i<COUNT; i++)); do
  ID=$((START_ID + i))
  IP_ADDRESS="${BASE_IP}.$((60 + i))"
  HOSTNAME="wp-lxc-$((i+1))"
  
  echo "Creating container $ID with hostname $HOSTNAME and IP $IP_ADDRESS"
  
  # Maak de container met de juiste specs (30GB disk, 1 core, 1GB RAM, 50MB/s)
  pct create $ID $TEMPLATE \
    --hostname $HOSTNAME \
    --memory 1024 \
    --cores 1 \
    --storage $STORAGE \
    --rootfs 30 \
    --net0 name=eth0,bridge=vmbr0,ip=$IP_ADDRESS/24,gw=${BASE_IP}.1,rate=50
  
  # Start de container
  pct start $ID
  
  # Wacht tot de container is opgestart
  sleep 10
  
  echo "Container $ID created and started"
done

echo "All containers created successfully"