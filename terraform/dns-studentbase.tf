# studentbase.app moved onto this box from StudentBase's own terraform, which still
# owns everything not tied to a specific droplet (CDN, cert, mail/spf/icloud records).
# `www` isn't here — it's a CNAME to `@` in StudentBase's domain.tf.
#
# Imported (not created fresh) from StudentBase's state on 2026-08-09:
#
#   terraform import digitalocean_domain.studentbase          studentbase.app
#   terraform import digitalocean_record.studentbase_api  studentbase.app,136615274
#   terraform import digitalocean_record.studentbase_apex studentbase.app,136615275
#
# A resource, not a data source: this repo is now sole owner of the zone, so
# `terraform destroy` (or deleting this block) deletes it and everything under it.
resource "digitalocean_domain" "studentbase" {
  name = "studentbase.app"
}

resource "digitalocean_record" "studentbase_api" {
  domain = digitalocean_domain.studentbase.id
  type   = "A"
  name   = "api"
  value  = hcloud_server.hub.ipv4_address
  ttl    = 300
}

resource "digitalocean_record" "studentbase_apex" {
  domain = digitalocean_domain.studentbase.id
  type   = "A"
  name   = "@"
  value  = hcloud_server.hub.ipv4_address
  ttl    = 300
}
