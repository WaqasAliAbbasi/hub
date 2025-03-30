module "deployments" {
  source = "./modules/deployments"

  kubernetes_host        = module.k3s_cluster.kubernetes_host
  client_certificate     = module.k3s_cluster.client_certificate
  client_key             = module.k3s_cluster.client_key
  cluster_ca_certificate = module.k3s_cluster.cluster_ca_certificate
}

output "admin_user_service_account_token" {
  value     = module.deployments.admin_user_service_account_token
  sensitive = true
}
