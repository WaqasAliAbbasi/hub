# Simplified K3s Kubernetes Cluster

This Terraform configuration creates a lightweight K3s Kubernetes cluster on DigitalOcean.

## Setup

```sh
ssh-keygen -t rsa -b 4096

# Make sure you have your SSH key ready
ls ~/.ssh/id_rsa.pub
   
# And kubectl installed
kubectl version --client

# Edit terraform.tfvars with your DigitalOcean token
cp terraform.tfvars.example terraform.tfvars

traform init -backend-config="access_key=" -backend-config="secret_key="

terraform plan
terraform apply
```

## Usage

### Access the cluster:
```bash
mkdir -p ~/.kube
# Get kubeconfig
terraform output -raw kubeconfig | base64 -d > ~/.kube/hub-config
export KUBECONFIG=~/.kube/hub-config

# Check cluster
kubectl get nodes
kubectl get pods -A

# Use k9s for management
k9s
```
