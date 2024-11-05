#!/bin/bash

#!/bin/bash

# Fetch instances and their names
instances=$(aws ec2 describe-instances --query 'Reservations[].Instances[].[InstanceId, Tags[?Key==`Name`].Value | [0]]' --filters "Name=instance-state-name,Values=running" --output text)

# Prepare an array for selection
options=()
while IFS=$'\t' read -r instance_id instance_name; do
    if [ -n "$instance_name" ]; then
        options+=("$instance_name ($instance_id)")
    fi
done <<< "$instances"

# Display options and get user input
echo "Select an instance by number:"
for i in "${!options[@]}"; do
    echo "$((i + 1)). ${options[i]}"
done

# Read user selection
read -p "Enter the number of the instance: " choice

# Validate choice and extract the instance ID
if [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -le "${#options[@]}" ] && [ "$choice" -gt 0 ]; then
    instance_id=$(echo "${options[$((choice - 1))]}" | sed -E 's/.*\(([^\)]+)\).*/\1/')

    # Start the SSM session
    aws ssm start-session --target "$instance_id"
else
    echo "Invalid selection."
fi

exit 0
