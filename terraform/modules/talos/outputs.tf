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

output "client_certificate" {
  value     = base64decode(talos_machine_secrets.machine_secrets.client_configuration.client_certificate)
  sensitive = true
}

output "client_key" {
  value     = base64decode(talos_machine_secrets.machine_secrets.client_configuration.client_key)
  sensitive = true
}

output "ca_certificate" {
  value     = base64decode(talos_machine_secrets.machine_secrets.client_configuration.ca_certificate)
  sensitive = true
}
