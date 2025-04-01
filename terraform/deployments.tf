module "deployments" {
  source = "./modules/deployments"

  kubernetes_endpoint    = module.talos_cluster.kubernetes_host
  host_ip_address        = module.talos_cluster.hub_ip
  client_certificate     = module.talos_cluster.kubernetes_client_certificate
  client_key             = module.talos_cluster.kubernetes_client_key
  cluster_ca_certificate = module.talos_cluster.kubernetes_ca_certificate
}
