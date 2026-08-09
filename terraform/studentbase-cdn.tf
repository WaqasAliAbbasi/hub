# Everything StudentBase's own Terraform used to manage that isn't tied to a specific
# droplet: the CDN serving content.studentbase.app, its certificate, the Spaces
# bucket behind it, and the mail/SPF/DKIM/icloud DNS records. See
# docs/studentbase-cutover.md. `digitalocean_domain.studentbase`, `prod_api`,
# and `prod_frontend` are in dns-studentbase.tf — split out because those are the
# routing-relevant records; this file is everything else.
#
# The old prod DB backup bucket (sb-prod-backup) that used to live here was deleted
# 2026-08-09 — StudentBase's Postgres now backs up through Hub's restic job
# (personal-hub-backups), so a separate Spaces bucket of ad-hoc SQL dumps was
# redundant.
#
# The certificate is DigitalOcean's own managed Let's Encrypt cert (type =
# "lets_encrypt"), not uploaded via the acme provider — DO renews it automatically,
# the same way Traefik renews every other cert on this box, with no Terraform
# involvement ever again. Only available because DNS for studentbase.app is on DO
# already (a prerequisite for this mode); confirmed working since dns-studentbase.tf
# already manages records here.
#
# This replaced an earlier version of this file that issued the cert via the
# vancluever/acme provider (tls_private_key + acme_registration + acme_certificate,
# DNS-01 challenge) — deliberately not imported from StudentBase's old Terraform,
# since ACME has no "read my key back" operation, so a fresh cert was the only option
# either way. That version worked but left the exact renewal problem it was replacing:
# nothing reissues the cert without a human or automation running `terraform apply`
# periodically. DO's managed mode has no such gap.
#
# All 14 real resources in this file and dns-studentbase.tf were imported and applied
# 2026-08-09 — the import commands that were here are done, not reference material.
# Switching to this DO-managed cert destroys the now-unused acme chain, which
# revokes the briefly-live acme-issued cert (`revoke_certificate_on_destroy` defaults
# true) — harmless, it was replaced within the same session it was created.
#
# One cleanup step remains from the original cutover: the *original* uploaded cert
# from StudentBase's old Terraform (`LetsEncryptTerraform8a0ff1bb`) is still sitting
# at DO, unmanaged by anything, no longer referenced by the CDN. Delete it by hand:
#
#   curl -X DELETE -H "Authorization: Bearer $DO_TOKEN" \
#     https://api.digitalocean.com/v2/certificates/7d8c0447-f374-4db6-81c9-4f49cf5f5baf

resource "digitalocean_certificate" "studentbase_cdn" {
  name    = "studentbase-cdn"
  type    = "lets_encrypt"
  domains = ["content.studentbase.app"]

  lifecycle {
    create_before_destroy = true
  }
}

resource "digitalocean_spaces_bucket" "studentbase_cdn" {
  name   = "sb-cdn-prod"
  region = "sgp1"
  acl    = "private"
}

resource "digitalocean_cdn" "studentbase" {
  origin           = digitalocean_spaces_bucket.studentbase_cdn.bucket_domain_name
  custom_domain    = "content.studentbase.app"
  certificate_name = digitalocean_certificate.studentbase_cdn.name
  ttl              = 3600

  depends_on = [digitalocean_certificate.studentbase_cdn]
}

resource "digitalocean_record" "studentbase_content" {
  domain = digitalocean_domain.studentbase.id
  type   = "CNAME"
  name   = "content"
  value  = "${digitalocean_cdn.studentbase.endpoint}."
  ttl    = 1800
}

# CNAME to the apex, same as before — not the same record as prod_frontend/prod_api
# in dns-studentbase.tf, which are the A records the apex/api actually resolve to.
resource "digitalocean_record" "studentbase_www" {
  domain = digitalocean_domain.studentbase.id
  type   = "CNAME"
  name   = "www"
  value  = "@"
  ttl    = 1800
}

resource "digitalocean_record" "studentbase_spf" {
  domain = digitalocean_domain.studentbase.id
  type   = "TXT"
  name   = "@"
  value  = "v=spf1 include:icloud.com ~all"
  ttl    = 3600
}

resource "digitalocean_record" "studentbase_icloud_domain" {
  domain = digitalocean_domain.studentbase.id
  type   = "TXT"
  name   = "@"
  value  = "apple-domain=Wf314O36cdfML1cD"
  ttl    = 3600
}

resource "digitalocean_record" "studentbase_icloud_dkim" {
  domain = digitalocean_domain.studentbase.id
  type   = "CNAME"
  name   = "sig1._domainkey"
  value  = "sig1.dkim.studentbase.app.at.icloudmailadmin.com."
  ttl    = 1800
}

resource "digitalocean_record" "studentbase_dmarc" {
  domain = digitalocean_domain.studentbase.id
  type   = "TXT"
  name   = "_dmarc"
  value  = "v=DMARC1; p=none;"
  ttl    = 1800
}

# Postmark's DKIM selector name is date-stamped by Postmark itself at setup time —
# it is not a mistake that this looks like a timestamp, and it does not need updating
# on any schedule.
resource "digitalocean_record" "studentbase_postmark_dkim" {
  domain = digitalocean_domain.studentbase.id
  type   = "TXT"
  name   = "20250817055129pm._domainkey"
  value  = "k=rsa;p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCO52vcP8qJIbWg/mUoSKCPe0w9q7UBgfaHLaaJoTKef7excavzGu7AhEAbthatL8i1cPXjB7krK3DDwXlTyinCRNtaoFgWEzktBvShygoyylRlSnQQtsZ81qxN7B5R73FhxRSkluU7/6JfciU9dxZbKcna1KihSxmqydXR+FZwFwIDAQAB"
  ttl    = 1800
}

resource "digitalocean_record" "studentbase_postmark_bounces" {
  domain = digitalocean_domain.studentbase.id
  type   = "CNAME"
  name   = "pm-bounces"
  value  = "pm.mtasv.net."
  ttl    = 1800
}

resource "digitalocean_record" "studentbase_icloud_mx" {
  for_each = toset(["mx01.mail.icloud.com.", "mx02.mail.icloud.com."])

  domain   = digitalocean_domain.studentbase.id
  type     = "MX"
  name     = "@"
  value    = each.key
  priority = 10
  ttl      = 3600
}
