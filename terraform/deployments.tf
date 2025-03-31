module "deployments" {
  source = "./modules/deployments"

  kubernetes_host        = module.talos_cluster.hub_kubeconfig.kubernetes_client_configuration.host
  client_certificate     = base64decode(module.talos_cluster.hub_kubeconfig.kubernetes_client_configuration.client_certificate)
  client_key             = base64decode(module.talos_cluster.hub_kubeconfig.kubernetes_client_configuration.client_key)
  cluster_ca_certificate = base64decode(module.talos_cluster.hub_kubeconfig.kubernetes_client_configuration.ca_certificate)
}
