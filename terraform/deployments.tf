module "deployments" {
  source = "./modules/deployments"

  hub_ip                 = module.talos_cluster.hub_ip
  kubernetes_host        = module.talos_cluster.kubernetes_host
  client_certificate     = module.talos_cluster.kubernetes_client_certificate
  client_key             = module.talos_cluster.kubernetes_client_key
  cluster_ca_certificate = module.talos_cluster.kubernetes_ca_certificate
}
