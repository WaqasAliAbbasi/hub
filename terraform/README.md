# Terraform

```sh
terraform init -backend-config="access_key=" -backend-config="secret_key="
terraform apply
```

## How to access via kubectl?

```sh
terraform output hub_password
host=$(terraform output -raw hub_ip_address)
scp root@$host:/etc/rancher/k3s/k3s.yaml ~/.kube/config
sed -i "s/127.0.0.1/$host/g" ~/.kube/config
```


## Kubernetes Dashboard

```sh
# Use this in the UI
terraform output admin_user_service_account_token
kubectl port-forward svc/kubernetes-dashboard-kong-proxy 8443:443
```
