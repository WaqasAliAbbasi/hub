module "k3s_cluster" {
  source = "./modules/k3s"

  digitalocean_token = var.digitalocean_token
}

output "hub_ip_address" {
  value = module.k3s_cluster.hub_ip_address
}

output "hub_password" {
  value     = module.k3s_cluster.hub_password
  sensitive = true
}
