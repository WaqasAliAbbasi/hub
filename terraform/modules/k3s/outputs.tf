output "hub_ip_address" {
  value = digitalocean_droplet.hub_01.ipv4_address
}

output "hub_password" {
  value     = random_password.hub_01_password.result
  sensitive = true
}

output "kubernetes_host" {
  value = "https://${digitalocean_droplet.hub_01.ipv4_address}:6443"
}

output "client_certificate" {
  value = base64decode(yamldecode(data.remote_file.k3s_config.content).users.0.user.client-certificate-data)
}

output "client_key" {
  value = base64decode(yamldecode(data.remote_file.k3s_config.content).users.0.user.client-key-data)
}

output "cluster_ca_certificate" {
  value = base64decode(yamldecode(data.remote_file.k3s_config.content).clusters.0.cluster.certificate-authority-data)
}
