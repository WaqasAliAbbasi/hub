# studentbase.app used to be managed by StudentBase's own deployment/terraform,
# pointing these two records at its own droplet. Phase 4 of PLAN.md moved the app
# onto this box (see docs/studentbase-cutover.md); these records moved with it, so a
# `terraform apply` here — not over there — is what can now change where
# studentbase.app resolves. StudentBase's terraform keeps everything that isn't
# tied to a specific droplet: the CDN, its certificate, and the mail/spf/icloud
# records.
#
# `www` is not here: it is a CNAME to `@` (StudentBase's domain.tf), so it follows
# whatever `@` resolves to without a record of its own.
#
# Imported, not created fresh — the records already existed and were detached from
# StudentBase's state with `terraform state rm` during the cutover. Run once, after
# `terraform init`, before the first `apply` that touches this file:
#
#   terraform import digitalocean_domain.studentbase          studentbase.app
#   terraform import digitalocean_record.studentbase_api  studentbase.app,136615274
#   terraform import digitalocean_record.studentbase_apex studentbase.app,136615275
#
# `terraform plan` should come back clean (or with only a TTL bump, 60 -> 300) once
# the import succeeds — anything else means the import targeted the wrong record.
#
# A resource, not a data source, as of 2026-08-09 — this repo is the sole owner of
# the studentbase.app zone now that StudentBase's own Terraform is gone, so it's the
# thing that should be able to recreate it from scratch if the zone ever needs it.
# The flip side: `terraform destroy` (or deleting this block) now deletes the zone
# and every record under it, not just refuses to find it.
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
