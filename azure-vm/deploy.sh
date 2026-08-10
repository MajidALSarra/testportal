#!/usr/bin/env bash
# Deploys a Windows cloud PC on Azure, reachable via RDP from anywhere.
#
# Prerequisites:
#   - Azure CLI installed (https://aka.ms/azure-cli) and logged in: az login
#
# Usage:
#   ./deploy.sh                          # interactive: prompts for password
#   ADMIN_PASSWORD='...' ./deploy.sh     # non-interactive
#
# Configurable via environment variables:
#   RESOURCE_GROUP  (default: cloudpc-rg)
#   LOCATION        (default: eastus)
#   VM_NAME         (default: cloudpc)
#   ADMIN_USERNAME  (default: azureuser)
#   VM_SIZE         (default: Standard_B2s  — 2 vCPU / 4 GB, minimum for a usable desktop)
#   OS_TYPE         (default: win11        — or server2022)

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-cloudpc-rg}"
LOCATION="${LOCATION:-eastus}"
VM_NAME="${VM_NAME:-cloudpc}"
ADMIN_USERNAME="${ADMIN_USERNAME:-azureuser}"
VM_SIZE="${VM_SIZE:-Standard_B2s}"
OS_TYPE="${OS_TYPE:-win11}"

if ! command -v az >/dev/null 2>&1; then
  echo "ERROR: Azure CLI (az) is not installed. Install it from https://aka.ms/azure-cli and run 'az login'." >&2
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo "ERROR: Not logged in to Azure. Run 'az login' first." >&2
  exit 1
fi

if [[ -z "${ADMIN_PASSWORD:-}" ]]; then
  echo "Choose the Windows admin password (12+ chars, mixing upper/lower/digit/symbol)."
  read -r -s -p "Password: " ADMIN_PASSWORD; echo
  read -r -s -p "Confirm:  " CONFIRM; echo
  if [[ "$ADMIN_PASSWORD" != "$CONFIRM" ]]; then
    echo "ERROR: Passwords do not match." >&2
    exit 1
  fi
fi

echo "==> Creating resource group '$RESOURCE_GROUP' in $LOCATION"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

echo "==> Deploying VM '$VM_NAME' ($VM_SIZE, $OS_TYPE) — this takes a few minutes"
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$(dirname "$0")/main.bicep" \
  --parameters \
    vmName="$VM_NAME" \
    adminUsername="$ADMIN_USERNAME" \
    adminPassword="$ADMIN_PASSWORD" \
    vmSize="$VM_SIZE" \
    osType="$OS_TYPE" \
  --query 'properties.outputs' \
  --output json > /tmp/cloudpc-outputs.json

PUBLIC_IP=$(az network public-ip show \
  --resource-group "$RESOURCE_GROUP" \
  --name "${VM_NAME}-ip" \
  --query ipAddress --output tsv)

echo
echo "============================================================"
echo " Your cloud PC is ready."
echo
echo "   Public IP:  $PUBLIC_IP"
echo "   Username:   $ADMIN_USERNAME"
echo
echo " Connect from any device with an RDP client:"
echo "   Windows:      run 'mstsc /v:$PUBLIC_IP'"
echo "   Mac/iOS:      'Windows App' from the App Store, add PC $PUBLIC_IP"
echo "   Android:      'Microsoft Remote Desktop' from Play Store"
echo "   Linux:        remmina or 'xfreerdp /v:$PUBLIC_IP /u:$ADMIN_USERNAME'"
echo
echo " To stop paying for compute while not using it:"
echo "   az vm deallocate -g $RESOURCE_GROUP -n $VM_NAME"
echo " To start it again:"
echo "   az vm start -g $RESOURCE_GROUP -n $VM_NAME"
echo " To delete everything:"
echo "   az group delete --name $RESOURCE_GROUP --yes"
echo "============================================================"
