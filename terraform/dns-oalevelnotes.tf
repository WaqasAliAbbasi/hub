# oalevelnotes.com — registered at GoDaddy, moved from Cloudflare DNS to DigitalOcean.
# The old DO App Platform site is retired; apex and www now point at hub and get
# redirected to studentbase.app by Traefik (dynamic/oalevelnotes-redirect.yml).
# No MX/TXT/SPF/DMARC/CAA existed at Cloudflare, so nothing else to import.
#
# A resource, not a data source — this repo owns the zone once GoDaddy's
# nameservers are repointed; `terraform destroy` deletes it and everything under it.
resource "digitalocean_domain" "oalevelnotes" {
  name = "oalevelnotes.com"
}

resource "digitalocean_record" "oalevelnotes_apex" {
  domain = digitalocean_domain.oalevelnotes.id
  type   = "A"
  name   = "@"
  value  = hcloud_server.hub.ipv4_address
  ttl    = 300
}

resource "digitalocean_record" "oalevelnotes_apex_v6" {
  domain = digitalocean_domain.oalevelnotes.id
  type   = "AAAA"
  name   = "@"
  value  = hcloud_server.hub.ipv6_address
  ttl    = 300
}

resource "digitalocean_record" "oalevelnotes_www" {
  domain = digitalocean_domain.oalevelnotes.id
  type   = "CNAME"
  name   = "www"
  value  = "@"
  ttl    = 300
}
