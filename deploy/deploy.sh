#!/bin/bash

# Login and Set Subscription
# az login
# az account set --subscription "YOUR_SUBSCRIPTION_ID"

RESOURCE_GROUP="rg-visitor-analytics"
LOCATION="eastus"
DB_PASSWORD="YourStrongPassword123!"

# Create Resource Group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Deploy Bicep Template
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters dbPassword=$DB_PASSWORD
