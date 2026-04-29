# Azure Hello World on AKS — Complete CLI Reference

> **Resource Group:** `CDPInterns-2473979-RG` | **Location:** `centralus` | **DockerHub:** `allenjose211`

---

## Fixed Values — Use These Throughout

```
Resource Group : CDPInterns-2473979-RG
Location       : centralus
DockerHub User : allenjose211
VNet Name      : helloworld-vnet
VNet CIDR      : 10.0.0.0/24
VM Subnet      : 10.0.0.0/27   (vm-subnet)
AKS Subnet     : 10.0.0.64/26  (aks-subnet)
Service CIDR   : 10.1.0.0/16
DNS Service IP : 10.1.0.10
```

---

## STEP 1 — Storage Account, Container & Blob Upload

### 1.1 — Create Storage Account

> ⚠️ Drop `--enable-blob-public-access` flag — older Az CLI on Cloud Shell does not support it.

```bash
az storage account create --name helloworldstore2026 --resource-group CDPInterns-2473979-RG --location centralus --sku Standard_LRS --kind StorageV2
```

✅ Look for `"provisioningState": "Succeeded"`

---

### 1.2 — Enable Soft Delete (30-day retention)

```bash
az storage blob service-properties delete-policy update --account-name helloworldstore2026 --enable true --days-retained 30
```

✅ Output shows `"enabled": true` and `"days": 30`

> **Portal verify:** Storage Account → Data management → Data protection → Soft delete for blobs = 30 days

---

### 1.3 — IP Restriction

```bash
# Get your public IP
curl ifconfig.me
```

```bash
# Deny all traffic by default
az storage account update --name helloworldstore2026 --resource-group CDPInterns-2473979-RG --default-action Deny
```

```bash
# Whitelist your IP — replace YOUR_IP with output from curl above
az storage account network-rule add --account-name helloworldstore2026 --resource-group CDPInterns-2473979-RG --ip-address YOUR_IP
```

✅ `networkRuleSet` shows `defaultAction: Deny` and your IP in `ipRules`

> **Portal verify:** Storage Account → Security + networking → Networking → Firewall and virtual networks

---

### 1.4 — Create Container and Upload Files

> ⚠️ Use `--auth-mode login` instead of `--public-access blob`. Public access is blocked by org policy.

```bash
# Create container
az storage container create --account-name helloworldstore2026 --name helloworld-assets --auth-mode login
```

```bash
# Get storage key
$STORAGE_KEY=$(az storage account keys list --account-name helloworldstore2026 --resource-group CDPInterns-2473979-RG --query "[0].value" -o tsv)
```

```bash
# Verify key is stored
echo $STORAGE_KEY
```

```bash
# Create sample files to upload
echo "Hello World Notes" > notes.txt
echo "placeholder image" > background.jpg
```

```bash
# Upload text file
az storage blob upload --account-name helloworldstore2026 --container-name helloworld-assets --name notes.txt --file ./notes.txt --account-key $STORAGE_KEY
```

```bash
# Upload image file
az storage blob upload --account-name helloworldstore2026 --container-name helloworld-assets --name background.jpg --file ./background.jpg --account-key $STORAGE_KEY
```

✅ Both files visible in Portal: Storage Account → Containers → helloworld-assets

---

## STEP 2 — Virtual Network & Subnets

> ⚠️ Use `/24` VNet (256 IPs) not `/26`. AKS needs a `/26` subnet minimum which cannot fit inside a `/26` VNet alongside a VM subnet.

### 2.1 — Create Virtual Network

```bash
az network vnet create --name helloworld-vnet --resource-group CDPInterns-2473979-RG --location centralus --address-prefix 10.0.0.0/24
```

✅ `provisioningState: Succeeded`

---

### 2.2 — Create VM Subnet

```bash
az network vnet subnet create --name vm-subnet --resource-group CDPInterns-2473979-RG --vnet-name helloworld-vnet --address-prefix 10.0.0.0/27
```

✅ `addressPrefix: 10.0.0.0/27` — covers IPs .0 to .31

---

### 2.3 — Create AKS Subnet

> ⚠️ Must be `/26` (64 IPs minimum). Use `10.0.0.64/26` to avoid overlap with vm-subnet.

```bash
az network vnet subnet create --name aks-subnet --resource-group CDPInterns-2473979-RG --vnet-name helloworld-vnet --address-prefix 10.0.0.64/26
```

✅ `addressPrefix: 10.0.0.64/26` — covers IPs .64 to .127

---

## STEP 3 — Linux VM & NSG

### 3.1 — Create NSG

```bash
az network nsg create --name helloworld-nsg --resource-group CDPInterns-2473979-RG --location centralus
```

---

### 3.2 — Add SSH Rule

> ⚠️ Org policy blocks rules with public source. Use `VirtualNetwork` as source — not `*` or `Internet`.

```bash
az network nsg rule create --nsg-name helloworld-nsg --resource-group CDPInterns-2473979-RG --name allow-ssh-vnet --priority 100 --protocol Tcp --destination-port-ranges 22 --access Allow --direction Inbound --source-address-prefix VirtualNetwork
```

---

### 3.3 — Add HTTP Rule

```bash
az network nsg rule create --nsg-name helloworld-nsg --resource-group CDPInterns-2473979-RG --name allow-http --priority 110 --protocol Tcp --destination-port-ranges 80 --access Allow --direction Inbound --source-address-prefix VirtualNetwork
```

---

### 3.4 — Create Linux VM

> ⚠️ Use `--public-ip-address ""` — org policy blocks public IPs on VMs. Access is via Azure Bastion only.

```bash
az vm create --name helloworld-vm --resource-group CDPInterns-2473979-RG --location centralus --image Ubuntu2204 --size Standard_B1s --admin-username azureuser --generate-ssh-keys --vnet-name helloworld-vnet --subnet vm-subnet --nsg helloworld-nsg --public-ip-address ""
```

✅ `powerState: VM running` — private IP will be `10.0.0.4`

---

## STEP 4 — Install Docker & Git on VM

> All commands run remotely via `az vm run-command` — no SSH needed since there is no public IP.

### 4.1 — Install Docker and Git

```bash
az vm run-command invoke --name helloworld-vm --resource-group CDPInterns-2473979-RG --command-id RunShellScript --scripts "sudo apt-get update -y && sudo apt-get install -y git && sudo apt-get install -y docker.io && sudo systemctl start docker && sudo systemctl enable docker && sudo usermod -aG docker azureuser"
```

> This takes 2-3 minutes.

---

### 4.2 — Verify Installation

```bash
az vm run-command invoke --name helloworld-vm --resource-group CDPInterns-2473979-RG --command-id RunShellScript --scripts "docker --version && git --version"
```

✅ stdout shows `Docker version 29.x` and `git version 2.x`

---

## STEP 5 — Create Hello World HTML File on VM

```bash
az vm run-command invoke --name helloworld-vm --resource-group CDPInterns-2473979-RG --command-id RunShellScript --scripts "mkdir -p /home/azureuser/helloworld && echo '<!DOCTYPE html><html><head><title>Hello World</title></head><body><h1>Hello World</h1><p>Deployed on Azure AKS</p></body></html>' > /home/azureuser/helloworld/index.html && cat /home/azureuser/helloworld/index.html"
```

✅ stdout shows the HTML content

---

## STEP 6 — Create Dockerfile, Build & Push Image

> ⚠️ Docker daemon does not run in Azure Cloud Shell. Run all commands in this step on your **local VirtualBox Ubuntu VM**.

### 6.1 — Create project folder and files

```bash
mkdir helloworld && cd helloworld
```

```bash
nano index.html
```

Paste this content and save with `Ctrl+X → Y → Enter`:

```html
<!DOCTYPE html>
<html>
<head><title>Hello World</title></head>
<body>
  <h1>Hello World</h1>
  <p>Deployed on Azure AKS</p>
</body>
</html>
```

```bash
nano Dockerfile
```

Paste this content and save with `Ctrl+X → Y → Enter`:

```dockerfile
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
```

> ⚠️ Do NOT add a `CMD` line. `nginx:alpine` has a built-in CMD. Adding CMD causes `CrashLoopBackOff`.

---

### 6.2 — Fix Docker permissions

```bash
sudo usermod -aG docker $USER && newgrp docker
```

---

### 6.3 — Build Docker image

```bash
docker build -t allenjose211/helloworld:v2 .
```

✅ `Successfully built` and `Successfully tagged allenjose211/helloworld:v2`

---

### 6.4 — Login and push to DockerHub

```bash
docker login -u allenjose211
```

```bash
docker push allenjose211/helloworld:v2
```

✅ `v2: digest: sha256:...` — image is on DockerHub permanently

---

## STEP 7 — Create AKS Cluster

> Run these commands back in **Azure Cloud Shell**.

### 7.1 — Get AKS Subnet ID

```bash
$AKS_SUBNET_ID=$(az network vnet subnet show --resource-group CDPInterns-2473979-RG --vnet-name helloworld-vnet --name aks-subnet --query id -o tsv)
```

```bash
echo $AKS_SUBNET_ID
```

---

### 7.2 — Create AKS Cluster

> ⚠️ `--service-cidr 10.1.0.0/16` is mandatory. Default `10.0.0.0/16` conflicts with our VNet range.

```bash
az aks create --name helloworld-aks --resource-group CDPInterns-2473979-RG --location centralus --node-count 1 --node-vm-size Standard_B2s --network-plugin azure --vnet-subnet-id $AKS_SUBNET_ID --generate-ssh-keys --enable-managed-identity --service-cidr 10.1.0.0/16 --dns-service-ip 10.1.0.10
```

> This takes 5-10 minutes. Do not close Cloud Shell.

✅ `provisioningState: Succeeded`

---

### 7.3 — Get kubectl Credentials

```bash
az aks get-credentials --name helloworld-aks --resource-group CDPInterns-2473979-RG
```

---

### 7.4 — Verify Node is Ready

```bash
kubectl get nodes
```

✅ Node status shows `Ready`

---

## STEP 8 — Deploy Hello World to AKS

> Open **Cloud Shell Editor** (click Editor button in toolbar). Create files using `File → New File`, paste content, save with `Ctrl+Shift+S`.

### 8.1 — Create deployment.yaml

Save as `deployment.yaml`:

```yaml
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
        image: allenjose211/helloworld:v2
        ports:
        - containerPort: 80
```

---

### 8.2 — Create service.yaml

Save as `service.yaml`:

```yaml
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
```

---

### 8.3 — Apply to AKS

```bash
kubectl apply -f deployment.yaml
```

```bash
kubectl apply -f service.yaml
```

---

### 8.4 — Watch for External IP

```bash
kubectl get service helloworld-service --watch
```

> Wait until `EXTERNAL-IP` shows an actual IP instead of `<pending>`. Press `Ctrl+C` once IP appears.

---

### 8.5 — Verify Pods are Running

```bash
kubectl get pods
```

✅ Both pods show `STATUS: Running` and `READY: 1/1`

> ⚠️ If pods show `CrashLoopBackOff` — your Docker image has a bad CMD line. Rebuild without CMD and push as v2.

---

### 8.6 — Open in Browser

```
http://EXTERNAL-IP
```

✅ You should see the Hello World page served from your custom Docker image.

---

## QUICK RESTART GUIDE — For New Lab Sessions

> If your lab session expires and resources are deleted, run only these commands. Steps 1-6 do not need to be repeated — the Docker image is on DockerHub permanently.

```bash
# 1. Create VNet
az network vnet create --name helloworld-vnet --resource-group CDPInterns-2473979-RG --location centralus --address-prefix 10.0.0.0/24
```

```bash
# 2. Create AKS Subnet
az network vnet subnet create --name aks-subnet --resource-group CDPInterns-2473979-RG --vnet-name helloworld-vnet --address-prefix 10.0.0.64/26
```

```bash
# 3. Get Subnet ID
$AKS_SUBNET_ID=$(az network vnet subnet show --resource-group CDPInterns-2473979-RG --vnet-name helloworld-vnet --name aks-subnet --query id -o tsv)
```

```bash
# 4. Create AKS Cluster (takes 5-10 mins)
az aks create --name helloworld-aks --resource-group CDPInterns-2473979-RG --location centralus --node-count 1 --node-vm-size Standard_B2s --network-plugin azure --vnet-subnet-id $AKS_SUBNET_ID --generate-ssh-keys --enable-managed-identity --service-cidr 10.1.0.0/16 --dns-service-ip 10.1.0.10
```

```bash
# 5. Get credentials
az aks get-credentials --name helloworld-aks --resource-group CDPInterns-2473979-RG
```

```bash
# 6. Create deployment.yaml and service.yaml in Editor (see Step 8 above)

# 7. Apply both files
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

```bash
# 8. Get External IP
kubectl get service helloworld-service --watch
```

---

## Errors Encountered & Fixes

| Error | Fix |
|---|---|
| `unrecognized arguments: --enable-blob-public-access true` | Remove the flag — older Az CLI on Cloud Shell does not support it |
| `Resource allow-ssh was disallowed by policy (Block-Public-Access-NSG-Rules)` | Use `--source-address-prefix VirtualNetwork` instead of `*` or `Internet` |
| `ServiceCidrOverlapExistingSubnetsCidr — 10.0.0.0/16 conflicts with 10.0.0.0/27` | Add `--service-cidr 10.1.0.0/16 --dns-service-ip 10.1.0.10` to `az aks create` |
| `InsufficientSubnetSize — 29 IPs needed but only 27 available in /27` | Expand aks-subnet from `/27` (32 IPs) to `/26` (64 IPs) |
| `CrashLoopBackOff on pods` | Remove `CMD` line from Dockerfile — `nginx:alpine` has a built-in CMD. Rebuild as `v2` |
| `Cannot connect to Docker daemon in Cloud Shell` | Build and push Docker image from local VirtualBox Ubuntu VM instead |
