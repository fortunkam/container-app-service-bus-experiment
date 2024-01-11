# Ensure an azure container registry is available containing the app

# Import variables from .env file

set -a # automatically export all variables
source .env
set +a

# Management Resource group
az group create --resource-group "$MGMT_RESOURCE_GROUP" --location "$LOCATION" -o table

# ACR
az acr create --name "$ACR_NAME" --resource-group "$MGMT_RESOURCE_GROUP" --sku "Standard" --admin-enabled false

# Build the app project and push to acr

az acr build --registry "$ACR_NAME" -t "demoapp:latest" ../app


