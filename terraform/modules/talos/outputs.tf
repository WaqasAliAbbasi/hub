output "hub_ip" {
  value = digitalocean_droplet.talos_control_plane.ipv4_address
}

output "hub_kubeconfig" {
  value     = talos_cluster_kubeconfig.kubeconfig
  sensitive = true
}

output "talos_config_raw" {
  sensitive = true
  value     = data.talos_client_configuration.talosconfig.talos_config
}

output "kubernetes_host" {
  value      = talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration.host
  depends_on = [null_resource.wait_for_host]
}

output "kubernetes_client_certificate" {
  value = base64decode(talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration.client_certificate)
}
output "kubernetes_client_key" {
  value = base64decode(talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration.client_key)
}
output "kubernetes_ca_certificate" {
  value = base64decode(talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration.ca_certificate)
}
