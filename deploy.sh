#!/bin/bash

#  ------------------------------------------------------------------------------------------
#  Copyright (c) Microsoft Corporation. All rights reserved.
#  Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
#  ------------------------------------------------------------------------------------------

###############################################################################################################################

# Pass name as argument
BASE=${1:-${USER}redwood}

# Set region (e.g. US South Central)
REGION=${2:-southcentralus}

# Credential file name
FILENAME=${3:-credentials.json}

# Resource group name
RESOURCE_GROUP="${BASE}-rg"

# Storage account name
STORAGE_ACCOUNT="${BASE}blob"

# Batch account name
BATCH_ACCOUNT="${BASE}batch"

# AAD app name
APP_NAME="${BASE}app"


###############################################################################################################################

# Get tenant + subscription id
TENANT_ID=`az account show --query tenantId --output tsv`
SUBSCRIPTION_ID=`az account show --query id --output tsv`

# Create resource group
az group create --name ${RESOURCE_GROUP} --location ${REGION}

# Create storage account
az storage account create --name ${STORAGE_ACCOUNT} --location ${REGION} --resource-group ${RESOURCE_GROUP} --sku Standard_LRS

# Create batch account
az batch account create --name ${BATCH_ACCOUNT} --location ${REGION} --resource-group ${RESOURCE_GROUP} --storage-account ${STORAGE_ACCOUNT}

# Register batch app
APP_ID=`az ad app create --display-name ${APP_NAME} | jq  -r '.appId'`

# Create service principal
az ad sp create --id $APP_ID

# Assign RBAC to application
az role assignment create --assignee $APP_ID --role "Contributor" --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Batch/batchAccounts/${BATCH_ACCOUNT}"

# Retrieve credentials
STORAGE_CREDENTIALS=`az storage account keys list --account-name ${STORAGE_ACCOUNT} --resource-group ${RESOURCE_GROUP} | jq -r '.[1].value'`
BATCH_SECRET=`az ad app credential reset --id $APP_ID --append | jq  -r '.password'`

# Write to credential file
echo "{
    \"_AD_TENANT\": \"${TENANT_ID}\",
    \"_AD_BATCH_CLIENT_ID\": \"${APP_ID}\",
    \"_AD_SECRET_BATCH\": \"${BATCH_SECRET}\",
    \"_BATCH_ACCOUNT_URL\": \"https://${BATCH_ACCOUNT}.${REGION}.batch.azure.com\",
    \"_BATCH_RESOURCE\": \"https://batch.core.windows.net/\",
    \"_REGION\": \"${REGION}\",
    \"_STORAGE_ACCOUNT_NAME\": \"${STORAGE_ACCOUNT}\",
    \"_STORAGE_ACCOUNT_KEY\": \"${STORAGE_CREDENTIALS}\"
}" > $FILENAME
