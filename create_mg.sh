#!/bin/bash

# This script creates a list of new Azure Management Groups under the Tenant Root Group.

# --- Step 1: List existing management groups for context ---
echo "Fetching existing management groups..."
az account management-group list --output table

if [ $? -ne 0 ]; then
    echo "Warning: Could not list management groups. You may not have the required permissions, or there may be none."
fi

echo "" # Add a newline for better readability

# --- Step 2: Prompt for a list of Management Group names ---
read -p "Enter a comma-separated list of names for the new management groups: " mg_names_input

# --- Step 3: Create each Management Group in a loop ---
echo ""

# Set comma as the internal field separator to split the input string into an array
IFS=',' read -ra mg_names <<< "$mg_names_input"

# Keep track of successes and failures
success_count=0
fail_count=0
failed_groups=""

for name in "${mg_names[@]}"; do
    # Trim leading/trailing whitespace from the name
    trimmed_name=$(echo "$name" | xargs)

    if [ -z "$trimmed_name" ]; then
        continue # Skip if the name is empty after trimming
    fi

    # Create a unique ID from the name by removing spaces. This ID will be used for both the name and the display name.
    mg_id=$(echo "$trimmed_name" | tr -d ' ')

    echo "-----------------------------------------------------"
    echo "Creating management group with ID and Display Name: '$mg_id'..."

    # Create the management group. The unique ID is used for both --name and --display-name.
    # By not specifying a parent, it defaults to the Tenant Root Group.
    az account management-group create --name "$mg_id" --display-name "$mg_id"

    if [ $? -eq 0 ]; then
        echo "✅ Successfully created '$mg_id'."
        ((success_count++))
    else
        echo "❌ Error: Failed to create '$mg_id'."
        ((fail_count++))
        failed_groups+="- $mg_id (from input: '$trimmed_name')\n"
    fi
done

# --- Step 4: Final Summary ---
echo "-----------------------------------------------------"
echo ""
echo "Script finished."
echo "Successfully created: $success_count"
echo "Failed to create: $fail_count"

if [ $fail_count -gt 0 ]; then
    echo -e "\nFailed groups:\n$failed_groups"
    echo "Please check the names, your permissions, and try again for the failed groups."
    exit 1
fi

