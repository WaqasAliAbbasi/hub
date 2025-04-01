module "talos_cluster" {
  source = "./modules/talos"

  digitalocean_token = var.digitalocean_token
}

output "hub_ip" {
  value = module.talos_cluster.hub_ip
}

output "hub_kubeconfig_raw" {
  value     = module.talos_cluster.hub_kubeconfig.kubeconfig_raw
  sensitive = true
}

output "talos_config_raw" {
  sensitive = true
  value     = module.talos_cluster.talos_config_raw
}
