#!/bin/bash

# This script creates a new Azure Resource Group after prompting the user to select a subscription.

# --- Step 1: List subscriptions and prompt for selection ---
echo "Fetching available Azure subscriptions..."

# Get subscriptions in a table format for the user to view
az account list --output table

# Check if the previous command succeeded
if [ $? -ne 0 ]; then
    echo "Error: Failed to list Azure subscriptions. Please make sure you are logged in."
    exit 1
fi

echo "" # Add a newline for better readability

# Prompt the user to enter the subscription name or ID
read -p "Please enter the Subscription Name or ID you want to use: " subscription_selection

# --- Step 2: Set the selected subscription ---
echo ""
echo "Setting the active subscription to '$subscription_selection'..."
az account set --subscription "$subscription_selection"

# Check if setting the subscription was successful
if [ $? -ne 0 ]; then
    echo "Error: Could not set the subscription. Please check the name/ID and try again."
    exit 1
fi

echo "Successfully set active subscription."
echo ""

# --- Step 3: Prompt for Resource Group details ---
read -p "Enter a name for the new resource group: " rg_name
read -p "Enter the location for the resource group (e.g., eastus, westeurope): " location

# --- Step 4: Create the Resource Group ---
echo ""
echo "Creating resource group '$rg_name' in location '$location'..."

az group create --name "$rg_name" --location "$location"

# --- Step 5: Final confirmation ---
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Resource group '$rg_name' was created successfully in subscription '$subscription_selection'."
else
    echo ""
    echo "❌ Error: Failed to create the resource group."
    exit 1
fi
