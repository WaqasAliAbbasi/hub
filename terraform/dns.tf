# Get the existing waqasali.dev domain
data "digitalocean_domain" "main" {
  name = var.domain
}

# Create A record for the cluster (hub.waqasali.dev)
resource "digitalocean_record" "hub" {
  domain = data.digitalocean_domain.main.id
  type   = "A"
  name   = "hub"
  value  = digitalocean_droplet.k3s_cluster.ipv4_address
  ttl    = 300
}
