#!/bin/bash

# Read and parse JSON file using jq
NODES=$(jq -r '.nodes | to_entries[] | "\(.key):\(.value)"' dns.json)

# Display node names without "caprakurs" prefix and store in an associative array
declare -A NODE_MAP
echo "Available nodes:"
i=0
for entry in $NODES; do
  NODE_NAME=${entry%%:*}            # Extract node name (e.g., caprakurs-node0)
  NODE_IP=${entry#*:}               # Extract node IP or DNS
  DISPLAY_NAME=${NODE_NAME#caprakurs-} # Remove prefix
  NODE_MAP[$i]=$NODE_IP
  echo "$i) $DISPLAY_NAME"
  ((i++))
done

# Prompt the user for a selection
read -p "Enter the number of the node to SSH into: " selection

# Verify selection and SSH into the chosen machine
if [[ -n "${NODE_MAP[$selection]}" ]]; then
  ssh -i kurs_priv.pem ubuntu@"${NODE_MAP[$selection]}"
else
  echo "Invalid selection."
fi
