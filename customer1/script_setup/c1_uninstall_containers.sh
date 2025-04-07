#!/bin/bash

# Variables based on your original setup
START_ID=100
COUNT=2

echo "Starting container removal process..."

# Loop through all containers
for ((i=0; i<COUNT; i++)); do
  ID=$((START_ID + i))
  HOSTNAME="wp-lxc-$((i+1))"
  
  echo "Processing container $ID ($HOSTNAME)..."
  
  # Check if container exists
  if pct status $ID &>/dev/null; then
    echo "Container $ID exists, proceeding with removal..."
    
    # Check if container is in HA group and remove if needed
    if ha-manager status | grep -q "ct:$ID"; then
      echo "Removing container $ID from HA group..."
      ha-manager remove ct:$ID
      echo "Container $ID removed from HA group."
    else
      echo "Container $ID is not in HA group, skipping HA removal."
    fi
    
    # Check if container is running and stop it if needed
    if pct status $ID | grep -q "status: running"; then
      echo "Stopping container $ID..."
      pct stop $ID
      
      # Wait for container to stop
      for ((j=0; j<30; j++)); do
        if ! pct status $ID | grep -q "status: running"; then
          echo "Container $ID stopped successfully."
          break
        fi
        echo "Waiting for container $ID to stop... ($(($j+1))/30)"
        sleep 1
      done
      
      # Force stop if normal stop didn't work
      if pct status $ID | grep -q "status: running"; then
        echo "Container $ID did not stop gracefully, forcing stop..."
        pct stop $ID --force
        sleep 5
      fi
    else
      echo "Container $ID is already stopped."
    fi
    
    # Destroy container
    echo "Destroying container $ID..."
    pct destroy $ID
    echo "Container $ID destroyed."
  else
    echo "Container $ID does not exist, skipping..."
  fi
done

# Remove monitoring configuration if it exists
if [ -f "/etc/prometheus/targets/wordpress_targets.yml" ]; then
  echo "Removing monitoring configuration..."
  rm -f /etc/prometheus/targets/wordpress_targets.yml
  
fi

echo "All containers have been removed and cleaned up."
echo "To verify, run: pct list"