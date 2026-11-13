#!/usr/bin/env bash
# Packages the latest commit of Waypoint and deploys it to App Service.
# Usage: ./scripts/deploy-app-service.sh app-waypoint-name rg-waypoint-name
set -euo pipefail
export MSYS_NO_PATHCONV=1

NAME="${1:?Give the name of the web app as the first argument}"
RESOURCE_GROUP="${2:?Give the name of the resource group as the second argument}"


PLAN_NAME=asp-waypoint-$NAME
PLAN_SKU="${PLAN_SKU:-B1}" #Uses B1 if PLAN_SKU is unset or empty.  PLAN_SKU=B1
APP_NAME=app-waypoint-$NAME
RUNTIME="NODE:24-lts"


az appservice plan create \
  --name asp-waypoint-meilok \
  --resource-group "$RESOURCE_GROUP" \
  --is-linux \
  --sku "$PLAN_SKU" \
  --query provisioningState \
  --output tsv
 #--query defaultHostName \
az webapp create \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --plan "$PLAN_NAME" \
  --runtime "$RUNTIME" \
  --query provisioningState \
  --output tsv



az webapp config appsettings set \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --settings SCM_DO_BUILD_DURING_DEPLOYMENT=true \
  --query "[].name" \
  --output tsv

echo "==> $RESOURCE_GROUP $NAME "
./scripts/deploy-app-service.sh

APP_URL="https://$(az webapp show \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query defaultHostName \
  --output tsv)"

#difference between defaultHostName and provision

echo "==> Deploying to App Service: $APP_NAME"
ATTEMPTS=30 DELAY=1 ./scripts/health-check.sh "$APP_URL/health" "$(git rev-parse HEAD)"

IDENTITY_NAME=id-waypoint-pipeline-$NAME

# from liveclass
az identity create \
  --name "$IDENTITY_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query clientId \
   --output tsv 
 #--query name \ from liveclass
 
CLIENT_ID=$(az identity show \
  --name "$IDENTITY_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query clientId \
  --output tsv)

PRINCIPAL_ID=$(az identity show \
  --name "$IDENTITY_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query principalId \
  --output tsv)


SUBJECT_PREFIX=$(gh api "repos/{owner}/{repo}/actions/oidc/customization/sub" --jq .sub_claim_prefix)
echo "$SUBJECT_PREFIX"

# 2nd register federated-credentical
az identity federated-credential create \
  --name github-main-branch \
  --identity-name "$IDENTITY_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --issuer https://token.actions.githubusercontent.com \
  --subject "${SUBJECT_PREFIX}:ref:refs/heads/main" \
  --audiences api://AzureADTokenExchange \
  --query subject \
  --output tsv

SCOPE=$(az group show \
  --name "$RESOURCE_GROUP" \
  --query id \
  --output tsv)

#??
if [ -z "$(az role assignment list --scope "$SCOPE" --role Contributpr --query [0].id --output tsv )" ] ; then
  az role assignment create \
    --assignee-object-id "$PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --role Contributor \
    --scope "$SCOPE" \
    --output none
fi

gh secret set AZURE_CLIENT_ID --body "$CLIENT_ID"
gh secret set AZURE_TENANT_ID --body "$(az account show --query tenantId --output tsv)"
gh secret set AZURE_SUBSCRIPTION_ID --body "$(az account show --query id --output tsv)"

gh variable set AZURE_APP_NAME --body "$APP_NAME"
gh variable set AZURE_APP_URL --body "$APP_URL"
gh variable set AZURE_RESOURCE_GROUP --body "$RESOURCE_GROUP"

# Azure's own status sometimes says "Starting the site" for minutes after the app is up.
# The smoke test asks the app itself for the new commit instead.
echo "==> Finished. The health check confirms the new version."