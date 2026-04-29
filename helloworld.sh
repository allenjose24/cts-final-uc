#!/bin/bash
# =============================================================================
#  Azure Hello World on AKS — Complete Single Script
#  Run this in Azure Cloud Shell (Bash)
#  Usage: bash deploy_helloworld_aks.sh
# =============================================================================
#
#  WHAT THIS SCRIPT DOES (fully automated end to end):
#  1.  Creates Storage Account + soft delete + IP restriction + blob upload
#  2.  Creates Virtual Network + VM subnet + AKS subnet
#  3.  Creates NSG + Linux VM
#  4.  Installs Docker and Git on the Azure VM
#  5.  Creates Hello World HTML file on the Azure VM
#  6.  Creates Dockerfile on the Azure VM
#  7.  Docker login on the Azure VM using your DockerHub credentials
#  8.  Docker build on the Azure VM
#  9.  Docker push to DockerHub from the Azure VM
#  10. Creates AKS cluster
#  11. AKS pulls image from DockerHub and deploys Hello World
#  12. Prints the external IP — open in browser to see Hello World
#
#  HOW TO SHARE WITH A FRIEND:
#  Friend changes only the VARIABLES section below and runs:
#    bash deploy_helloworld_aks.sh
#
# =============================================================================



# =============================================================================
#  *** CHANGE THESE VARIABLES — Everything else runs automatically ***
# =============================================================================

# Azure settings
RESOURCE_GROUP="CDPInterns-2473979-RG"
LOCATION="centralus"
STORAGE_ACCOUNT_NAME="helloworldstore2026"
VNET_NAME="helloworld-vnet"
VM_NAME="helloworld-vm"
NSG_NAME="helloworld-nsg"
AKS_CLUSTER_NAME="helloworld-aks"
CONTAINER_NAME="helloworld-assets"

# DockerHub settings
DOCKERHUB_USERNAME="allenjose211"
DOCKERHUB_PASSWORD="your_password_here"
IMAGE_NAME="helloworld"
IMAGE_TAG="v2"

# Network settings — safe to leave as-is
VNET_CIDR="10.0.0.0/24"
VM_SUBNET_CIDR="10.0.0.0/27"
AKS_SUBNET_CIDR="10.0.0.64/26"
SERVICE_CIDR="10.1.0.0/16"
DNS_SERVICE_IP="10.1.0.10"

# =============================================================================
#  DO NOT CHANGE ANYTHING BELOW THIS LINE
# =============================================================================

DOCKER_IMAGE="$DOCKERHUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG"

step() {
  echo ""
  echo "======================================================"
  echo "  $1"
  echo "======================================================"
}
ok()   { echo "  ✅  $1"; }
info() { echo "  ℹ️   $1"; }
fail() {
  echo ""
  echo "  ❌  ERROR at: $1"
  echo "  Script stopped. Fix the error above and re-run."
  exit 1
}
check() { [ $? -ne 0 ] && fail "$1"; }

echo ""
echo "======================================================"
echo "  Azure Hello World on AKS — Full Auto Deployment"
echo "======================================================"
echo "  Resource Group  : $RESOURCE_GROUP"
echo "  Location        : $LOCATION"
echo "  Storage Account : $STORAGE_ACCOUNT_NAME"
echo "  VNet            : $VNET_NAME"
echo "  VM              : $VM_NAME"
echo "  AKS Cluster     : $AKS_CLUSTER_NAME"
echo "  Docker Image    : $DOCKER_IMAGE"
echo "======================================================"
echo ""
echo "  Starting in 3 seconds... (Ctrl+C to cancel)"
sleep 3



# =============================================================================
#  STEP 1 — STORAGE ACCOUNT
# =============================================================================

step "STEP 1 of 9 — Storage Account"

info "Creating storage account: $STORAGE_ACCOUNT_NAME ..."
az storage account create \
  --name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --output none
check "Storage account creation — name may already be taken. Change STORAGE_ACCOUNT_NAME."
ok "Storage account created"

info "Enabling soft delete — 30 day retention..."
az storage blob service-properties delete-policy update \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --enable true \
  --days-retained 30 \
  --output none
check "Soft delete configuration"
ok "Soft delete enabled — 30 days"

info "Getting your public IP..."
MY_IP=$(curl -s ifconfig.me)
check "Could not detect public IP"
ok "Your IP: $MY_IP"

info "Setting default network action to Deny..."
az storage account update \
  --name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --default-action Deny \
  --output none
check "Setting default action to Deny"
ok "All traffic denied by default"

info "Whitelisting your IP: $MY_IP ..."
az storage account network-rule add \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --ip-address "$MY_IP" \
  --output none
check "Whitelisting IP"
ok "Your IP whitelisted"

info "Creating blob container: $CONTAINER_NAME ..."
az storage container create \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --name "$CONTAINER_NAME" \
  --auth-mode login \
  --output none
check "Container creation"
ok "Container created"

info "Getting storage key..."
STORAGE_KEY=$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].value" -o tsv)
check "Getting storage key"

info "Creating and uploading sample files..."
echo "Hello World Notes" > notes.txt
echo "placeholder image" > background.jpg

az storage blob upload \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --container-name "$CONTAINER_NAME" \
  --name notes.txt \
  --file ./notes.txt \
  --account-key "$STORAGE_KEY" \
  --output none
check "Uploading notes.txt"

az storage blob upload \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --container-name "$CONTAINER_NAME" \
  --name background.jpg \
  --file ./background.jpg \
  --account-key "$STORAGE_KEY" \
  --output none
check "Uploading background.jpg"
ok "Files uploaded to container"

ok "STEP 1 COMPLETE"



# =============================================================================
#  STEP 2 — VIRTUAL NETWORK & SUBNETS
# =============================================================================

step "STEP 2 of 9 — Virtual Network & Subnets"

info "Creating VNet: $VNET_NAME ($VNET_CIDR)..."
az network vnet create \
  --name "$VNET_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --address-prefix "$VNET_CIDR" \
  --output none
check "VNet creation"
ok "VNet created — $VNET_CIDR"

info "Creating vm-subnet ($VM_SUBNET_CIDR)..."
az network vnet subnet create \
  --name vm-subnet \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --address-prefix "$VM_SUBNET_CIDR" \
  --output none
check "vm-subnet creation"
ok "vm-subnet created — $VM_SUBNET_CIDR"

info "Creating aks-subnet ($AKS_SUBNET_CIDR)..."
az network vnet subnet create \
  --name aks-subnet \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --address-prefix "$AKS_SUBNET_CIDR" \
  --output none
check "aks-subnet creation"
ok "aks-subnet created — $AKS_SUBNET_CIDR"

ok "STEP 2 COMPLETE"



# =============================================================================
#  STEP 3 — NSG & LINUX VM
# =============================================================================

step "STEP 3 of 9 — NSG & Linux VM"

info "Creating NSG: $NSG_NAME ..."
az network nsg create \
  --name "$NSG_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output none
check "NSG creation"
ok "NSG created"

info "Adding SSH inbound rule (VirtualNetwork scope)..."
az network nsg rule create \
  --nsg-name "$NSG_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --name allow-ssh-vnet \
  --priority 100 \
  --protocol Tcp \
  --destination-port-ranges 22 \
  --access Allow \
  --direction Inbound \
  --source-address-prefix VirtualNetwork \
  --output none
check "SSH NSG rule"
ok "SSH rule added"

info "Adding HTTP inbound rule (VirtualNetwork scope)..."
az network nsg rule create \
  --nsg-name "$NSG_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --name allow-http \
  --priority 110 \
  --protocol Tcp \
  --destination-port-ranges 80 \
  --access Allow \
  --direction Inbound \
  --source-address-prefix VirtualNetwork \
  --output none
check "HTTP NSG rule"
ok "HTTP rule added"

info "Creating Linux VM: $VM_NAME (this takes 2-3 mins)..."
az vm create \
  --name "$VM_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --vnet-name "$VNET_NAME" \
  --subnet vm-subnet \
  --nsg "$NSG_NAME" \
  --public-ip-address "" \
  --output none
check "VM creation"
ok "VM created — no public IP (Bastion access only)"

ok "STEP 3 COMPLETE"



# =============================================================================
#  STEP 4 — INSTALL DOCKER & GIT ON VM
# =============================================================================

step "STEP 4 of 9 — Installing Docker & Git on VM (2-3 mins)"

az vm run-command invoke \
  --name "$VM_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --command-id RunShellScript \
  --scripts "sudo apt-get update -y && sudo apt-get install -y git && sudo apt-get install -y docker.io && sudo systemctl start docker && sudo systemctl enable docker && sudo usermod -aG docker root" \
  --output none
check "Docker and Git installation on VM"
ok "Docker and Git installed on VM"

ok "STEP 4 COMPLETE"



# =============================================================================
#  STEP 5 — CREATE HELLO WORLD HTML ON VM
# =============================================================================

step "STEP 5 of 9 — Creating Hello World HTML on VM"

az vm run-command invoke \
  --name "$VM_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --command-id RunShellScript \
  --scripts "mkdir -p /home/azureuser/helloworld && echo '<!DOCTYPE html><html><head><title>Hello World</title></head><body><h1>Hello World</h1><p>Deployed on Azure AKS</p></body></html>' > /home/azureuser/helloworld/index.html && cat /home/azureuser/helloworld/index.html" \
  --output none
check "Hello World HTML creation on VM"
ok "index.html created on VM"

ok "STEP 5 COMPLETE"



# =============================================================================
#  STEP 6 — CREATE DOCKERFILE ON VM
# =============================================================================

step "STEP 6 of 9 — Creating Dockerfile on VM"

az vm run-command invoke \
  --name "$VM_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --command-id RunShellScript \
  --scripts "printf 'FROM nginx:alpine\nCOPY index.html /usr/share/nginx/html/index.html\nEXPOSE 80\n' > /home/azureuser/helloworld/Dockerfile && cat /home/azureuser/helloworld/Dockerfile" \
  --output none
check "Dockerfile creation on VM"
ok "Dockerfile created on VM"

ok "STEP 6 COMPLETE"



# =============================================================================
#  STEP 7 — DOCKER LOGIN + BUILD + PUSH ON VM
# =============================================================================

step "STEP 7 of 9 — Docker Login on VM"

az vm run-command invoke \
  --name "$VM_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --command-id RunShellScript \
  --scripts "echo '$DOCKERHUB_PASSWORD' | docker login -u '$DOCKERHUB_USERNAME' --password-stdin" \
  --output none
check "Docker login — check DOCKERHUB_USERNAME and DOCKERHUB_PASSWORD variables"
ok "Logged in to DockerHub as $DOCKERHUB_USERNAME"

step "STEP 7 of 9 — Docker Build on VM"

az vm run-command invoke \
  --name "$VM_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --command-id RunShellScript \
  --scripts "cd /home/azureuser/helloworld && docker build -t $DOCKER_IMAGE ." \
  --output none
check "Docker build on VM"
ok "Image built: $DOCKER_IMAGE"

step "STEP 7 of 9 — Docker Push to DockerHub"

az vm run-command invoke \
  --name "$VM_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --command-id RunShellScript \
  --scripts "docker push $DOCKER_IMAGE" \
  --output none
check "Docker push to DockerHub"
ok "Image pushed to DockerHub: $DOCKER_IMAGE"

ok "STEP 7 COMPLETE"



# =============================================================================
#  STEP 8 — CREATE AKS CLUSTER
# =============================================================================

step "STEP 8 of 9 — Creating AKS Cluster (5-10 mins, please wait)"

info "Getting AKS subnet resource ID..."
AKS_SUBNET_ID=$(az network vnet subnet show \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --name aks-subnet \
  --query id -o tsv)
check "Getting AKS subnet ID"
ok "AKS subnet ID retrieved"

info "Creating AKS cluster: $AKS_CLUSTER_NAME ..."
az aks create \
  --name "$AKS_CLUSTER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --node-count 1 \
  --node-vm-size Standard_B2s \
  --network-plugin azure \
  --vnet-subnet-id "$AKS_SUBNET_ID" \
  --generate-ssh-keys \
  --enable-managed-identity \
  --service-cidr "$SERVICE_CIDR" \
  --dns-service-ip "$DNS_SERVICE_IP" \
  --output none
check "AKS cluster creation"
ok "AKS cluster created"

info "Configuring kubectl credentials..."
az aks get-credentials \
  --name "$AKS_CLUSTER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --overwrite-existing
check "Getting AKS credentials"
ok "kubectl configured"

info "Verifying node status..."
kubectl get nodes

ok "STEP 8 COMPLETE"



# =============================================================================
#  STEP 9 — DEPLOY HELLO WORLD TO AKS
# =============================================================================

step "STEP 9 of 9 — Deploying Hello World to AKS"

info "Creating deployment.yaml using image: $DOCKER_IMAGE ..."
cat > deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: helloworld-deployment
spec:
  replicas: 2
  selector:
    matchLabels:
      app: helloworld
  template:
    metadata:
      labels:
        app: helloworld
    spec:
      containers:
      - name: helloworld
        image: ${DOCKER_IMAGE}
        ports:
        - containerPort: 80
EOF
ok "deployment.yaml created"

info "Creating service.yaml..."
cat > service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: helloworld-service
spec:
  type: LoadBalancer
  selector:
    app: helloworld
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
EOF
ok "service.yaml created"

info "Applying deployment to AKS..."
kubectl apply -f deployment.yaml
check "kubectl apply deployment"

info "Applying service to AKS..."
kubectl apply -f service.yaml
check "kubectl apply service"

info "Waiting for pods to be ready..."
kubectl rollout status deployment/helloworld-deployment
check "Deployment rollout"
ok "Both pods are running"

info "Waiting for external IP (2-3 mins)..."
EXTERNAL_IP=""
ATTEMPTS=0
while [ -z "$EXTERNAL_IP" ] && [ $ATTEMPTS -lt 20 ]; do
  EXTERNAL_IP=$(kubectl get service helloworld-service \
    --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}" 2>/dev/null)
  if [ -z "$EXTERNAL_IP" ]; then
    echo "  ... waiting for IP (attempt $((ATTEMPTS+1))/20) ..."
    sleep 15
    ATTEMPTS=$((ATTEMPTS+1))
  fi
done

if [ -z "$EXTERNAL_IP" ]; then
  echo "  ⚠️  IP not assigned yet. Run manually:"
  echo "     kubectl get service helloworld-service --watch"
else
  ok "External IP assigned: $EXTERNAL_IP"
fi

ok "STEP 9 COMPLETE"



# =============================================================================
#  FINAL SUMMARY
# =============================================================================

echo ""
echo "======================================================"
echo "  DEPLOYMENT COMPLETE — ALL 9 STEPS DONE"
echo "======================================================"
echo ""
echo "  Resource Group  : $RESOURCE_GROUP"
echo "  Storage Account : $STORAGE_ACCOUNT_NAME"
echo "  VNet            : $VNET_NAME ($VNET_CIDR)"
echo "  VM              : $VM_NAME (Docker build machine)"
echo "  Docker Image    : $DOCKER_IMAGE (on DockerHub)"
echo "  AKS Cluster     : $AKS_CLUSTER_NAME (1 node)"
echo ""
if [ -n "$EXTERNAL_IP" ]; then
echo "  Open this in your browser:"
echo "  http://$EXTERNAL_IP"
echo ""
fi
echo "  Useful commands:"
echo "  kubectl get pods"
echo "  kubectl get service helloworld-service"
echo "  kubectl get nodes"
echo ""
echo "  To DELETE everything when done:"
echo "  az group delete --name $RESOURCE_GROUP --yes --no-wait"
echo ""
echo "======================================================"