data "digitalocean_domain" "main" {
  name = "waqasali.dev"
}

# One wildcard record covers every project forever: adding a service means adding a
# Traefik host label, with no DNS change and no Terraform run.
#
# The apex is deliberately untouched — waqasali.dev stays on GitHub Pages, and a
# wildcard does not shadow an explicit apex record.
resource "digitalocean_record" "wildcard" {
  domain = data.digitalocean_domain.main.id
  type   = "A"
  name   = "*"
  value  = hcloud_server.hub.ipv4_address
  ttl    = 300
}

resource "digitalocean_record" "wildcard_v6" {
  domain = data.digitalocean_domain.main.id
  type   = "AAAA"
  name   = "*"
  value  = hcloud_server.hub.ipv6_address
  ttl    = 300
}
