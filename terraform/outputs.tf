output "cluster_ip" {
  description = "Public IP address of the K3s cluster"
  value       = digitalocean_droplet.k3s_cluster.ipv4_address
}

output "cluster_name" {
  description = "Name of the K3s cluster"
  value       = digitalocean_droplet.k3s_cluster.name
}

output "kubeconfig" {
  description = "Base64 encoded kubeconfig for the cluster"
  value       = data.external.kubeconfig.result.kubeconfig
  sensitive   = true
}
