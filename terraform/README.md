# Terraform

```sh
terraform init -backend-config="access_key=" -backend-config="secret_key="
terraform apply
```

## K9s / kubectl

```sh
brew install siderolabs/tap/talosctl kubectl k9s
terraform output --raw hub_kubeconfig_raw > ~/.kube/config
k9s
```

## Dashboard

```sh
terraform output --raw talos_config_raw > ~/.talos/config
talosctl dashboard -e $(terraform output --raw hub_ip) -n $(terraform output --raw hub_ip)
```

## Test nginx example

```sh
curl --header 'Host: example.com' $(terraform output --raw hub_ip)
```