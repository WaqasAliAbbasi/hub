# oalevelnotes.com — registered at GoDaddy, DNS was on Cloudflare, moving to
# DigitalOcean so it can be managed here like waqasali.dev and studentbase.app.
# The static site used to live on a DigitalOcean App Platform app
# (oalevelnotes-g8huc) fronted by Cloudflare; that app is being retired, so
# both apex and www now point straight at hub and get redirected to
# studentbase.app by Traefik (stacks/traefik/dynamic/oalevelnotes-redirect.yml)
# instead of serving any content of their own.
#
# Current records at Cloudflare, queried 2026-08-09 before cutover, for
# reference: no MX/TXT/SPF/DMARC/CAA records exist on this domain — no email
# or other services configured, so nothing else needs to be imported.
#
# A resource, not a data source — this repo becomes the sole owner of the
# zone once GoDaddy's nameservers are repointed. `terraform destroy` (or
# deleting this block) deletes the zone and everything under it.
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
