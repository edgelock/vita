#!/bin/bash

#=======================================================================
# SYNOPSIS:
#   Audits and enforces minimum required tags for all resources in a
#   resource group using Azure CLI and jq.
#
# DESCRIPTION:
#   This script retrieves all resources in a specified resource group.
#   It checks each resource's tags against a list of required tags.
#   If a required tag is missing, it adds the tag with a default value.
#   This script MERGES tags; it does not overwrite existing, different tags.
#
# PRE-REQUISITES:
#   - Azure CLI (az)
#   - jq (for JSON manipulation)
#   - Log in: `az login`
#   - Set subscription: `az account set --subscription "Your-Subscription-ID"`
#=======================================================================

# --- START: Configuration ---

# 1. Specify the name of the resource group to target
RESOURCE_GROUP="example-skool"

# 2. Define your minimum required tags as a JSON string.
#    (Based on your provided image)
REQUIRED_TAGS_JSON=$(cat <<EOF
{
    "environment": "staging",
    "cov-request": "501",
    "deploymentMethod": "Manual",
    "resourceClass": "Infra",
    "Created By": "Jhante Charles"
}
EOF
)

# --- END: Configuration ---

# ANSI color codes
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
GRAY='\033[0;90m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${CYAN}--- Starting Tag Audit for Resource Group: '$RESOURCE_GROUP' ---${NC}"

# Check for jq
if ! command -v jq &> /dev/null
then
    echo -e "${RED}ERROR: 'jq' is not installed. This script cannot continue.${NC}"
    echo "Please install jq to proceed."
    exit 1
fi

# Get all resources, outputting a compact JSON array
# The "|| true" prevents the script from exiting if az resource list fails
# (e.g., empty RG), letting us handle the error below.
RESOURCE_LIST_JSON=$(az resource list --resource-group "$RESOURCE_GROUP" -o json || true)

if [ -z "$RESOURCE_LIST_JSON" ] || [ "$(echo "$RESOURCE_LIST_JSON" | jq 'length')" -eq 0 ]; then
    echo -e "${YELLOW}No resources found in resource group '$RESOURCE_GROUP'.${NC}"
    exit 0
fi

# Loop over each resource ID and its tags
# We use jq to parse the JSON array and feed a while-read loop
# This is a robust way to handle any special characters in names or tags
echo "$RESOURCE_LIST_JSON" | jq -c '.[] | {id: .id, name: .name, tags: .tags}' | while read -r resource_line; do
    
    # Extract the ID, Name, and Tags JSON for the current resource
    RESOURCE_ID=$(echo "$resource_line" | jq -r '.id')
    RESOURCE_NAME=$(echo "$resource_line" | jq -r '.name')
    CURRENT_TAGS_JSON=$(echo "$resource_line" | jq '.tags')

    echo "Checking: $RESOURCE_NAME"

    # If tags are 'null', set to an empty JSON object '{}' for merging
    if [ "$CURRENT_TAGS_JSON" == "null" ]; then
        CURRENT_TAGS_JSON="{}"
    fi

    # --- The Core Logic ---
    # Merge the required tags with the current tags using jq.
    # The syntax '$required + $current' merges two JSON objects.
    # If a key exists in both, the value from the *right-hand* object ($current) wins.
    # This perfectly achieves our goal: existing tags are preserved,
    # and missing required tags are added.
    MERGED_TAGS_JSON=$(jq -n \
                          --argjson required "$REQUIRED_TAGS_JSON" \
                          --argjson current "$CURRENT_TAGS_JSON" \
                          '$required + $current')

    # Compare the original tags JSON with the new merged tags JSON.
    # If they are different, an update is needed.
    if [ "$CURRENT_TAGS_JSON" != "$MERGED_TAGS_JSON" ]; then
        echo -e "  ${YELLOW}[MISSING] Tags are missing. Applying update...${NC}"
        
        # Apply the new, complete set of merged tags.
        # This command REPLACES all tags on the resource with the new merged set.
        if az resource update --ids "$RESOURCE_ID" --set tags="$MERGED_TAGS_JSON" -o none; then
            echo -e "  ${GREEN}Successfully updated tags for $RESOURCE_NAME.${NC}"
        else
            echo -e "  ${RED}FAILED to update tags for $RESOURCE_NAME.${NC}"
        fi
    else
        echo -e "  ${GRAY}All required tags are present. No update needed.${NC}"
    fi
    echo "--------------------"

done

echo -e "${CYAN}--- Tag Audit Complete ---${NC}"