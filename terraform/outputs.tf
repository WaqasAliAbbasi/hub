output "server_ipv4" {
  description = "Public IPv4 of the hub server"
  value       = hcloud_server.hub.ipv4_address
}

output "server_ipv6" {
  description = "Public IPv6 of the hub server"
  value       = hcloud_server.hub.ipv6_address
}

output "ssh" {
  description = "Shorthand for connecting as the deploy user"
  value       = "ssh deploy@${hcloud_server.hub.ipv4_address}"
}
