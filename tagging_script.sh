#!/bin/bash

#=======================================================================
# SYNOPSIS:
#   Audits and enforces minimum required tags based on resource type
#   for all resources in a resource group.
#
# DESCRIPTION:
#   This script retrieves all resources, checks their type, and applies
#   a specific set of required tags based on a lookup map.
#   If no specific rule exists, it applies a default set of tags.
#=======================================================================

# --- START: Configuration ---

# 1. Specify the name of the resource group to target
RESOURCE_GROUP="example-skool"

# 2. Define your *DEFAULT* required tags.
#    This set is used for any resource type NOT defined in the map below.
DEFAULT_TAGS_JSON=$(cat <<EOF
{
    "environment": "staging",
    "cov-request": "501",
    "deploymentMethod": "Manual",
    "resourceClass": "Infra",
    "Created By": "Jhante Charles"
}
EOF
)

# 3. Define your *SPECIFIC* tag sets for different resource types.
#    (This is the user's requested VNet tag set)
VNET_TAGS_JSON=$(cat <<EOF
{
    "environment": "staging",
    "cov-request": "501",
    "deploymentMethod": "Manual",
    "resourceClass": "Networking",
    "Created By": "Jhante Charles"
}
EOF
)

#    (Example for another type, e.g., Storage Accounts)
STORAGE_TAGS_JSON=$(cat <<EOF
{
    "environment": "staging",
    "cov-request": "501",
    "deploymentMethod": "Manual",
    "resourceClass": "Storage",
    "Created By": "Jhante Charles"
}
EOF
)

# 4. Create the Resource Type -> Tag Map
#    Syntax: TAG_MAP["<Full-Resource-Type-String>"]="$JSON_VARIABLE"
#    (This is a Bash Associative Array)
declare -A TAG_MAP

TAG_MAP["Microsoft.Network/virtualNetworks"]="$VNET_TAGS_JSON"
TAG_MAP["Microsoft.Network/networkSecurityGroups"]="$VNET_TAGS_JSON"
TAG_MAP["Microsoft.Storage/storageAccounts"]="$STORAGE_TAGS_JSON"

# --- END: Configuration ---

# ANSI color codes
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
GRAY='\033[0;90m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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
RESOURCE_LIST_JSON=$(az resource list --resource-group "$RESOURCE_GROUP" -o json || true)

if [ -z "$RESOURCE_LIST_JSON" ] || [ "$(echo "$RESOURCE_LIST_JSON" | jq 'length')" -eq 0 ]; then
    echo -e "${YELLOW}No resources found in resource group '$RESOURCE_GROUP'.${NC}"
    exit 0
fi

# --- MODIFIED LOOP ---
# We now also select the 'type' field from the resource JSON
echo "$RESOURCE_LIST_JSON" | jq -c '.[] | {id: .id, name: .name, type: .type, tags: .tags}' | while read -r resource_line; do
    
    # Extract the ID, Name, Type, and Tags JSON for the current resource
    RESOURCE_ID=$(echo "$resource_line" | jq -r '.id')
    RESOURCE_NAME=$(echo "$resource_line" | jq -r '.name')
    RESOURCE_TYPE=$(echo "$resource_line" | jq -r '.type') # <-- NEW
    CURRENT_TAGS_JSON=$(echo "$resource_line" | jq '.tags')

    echo "Checking: $RESOURCE_NAME (${GRAY}Type: $RESOURCE_TYPE${NC})"

    # If tags are 'null', set to an empty JSON object '{}' for merging
    if [ "$CURRENT_TAGS_JSON" == "null" ]; then
        CURRENT_TAGS_JSON="{}"
    fi

    # --- NEW LOGIC: Select the correct tag set ---
    
    local_required_tags_json="" # Holds the JSON for this specific resource
    
    # Check if the resource type exists as a key in our map
    if [[ -n "${TAG_MAP[$RESOURCE_TYPE]}" ]]; then
        # It exists. Use the specific tag set.
        echo -e "  ${BLUE}[INFO] Found specific rule for $RESOURCE_TYPE.${NC}"
        local_required_tags_json="${TAG_MAP[$RESOURCE_TYPE]}"
    else
        # It does not exist. Use the default tag set.
        echo -e "  ${GRAY}[INFO] No specific rule found. Using 'Default' tags.${NC}"
        local_required_tags_json="$DEFAULT_TAGS_JSON"
    fi
    # --- END: New Logic ---


    # --- The Core Logic (Modified) ---
    # Merge the *dynamically selected* required tags with the current tags.
    MERGED_TAGS_JSON=$(jq -n \
                          --argjson required "$local_required_tags_json" \
                          --argjson current "$CURRENT_TAGS_JSON" \
                          '$required + $current')

    # Compare the original tags JSON with the new merged tags JSON.
    if [ "$CURRENT_TAGS_JSON" != "$MERGED_TAGS_JSON" ]; then
        echo -e "  ${YELLOW}[MISSING] Tags are missing or rules changed. Applying update...${NC}"
        
        # Apply the new, complete set of merged tags.
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