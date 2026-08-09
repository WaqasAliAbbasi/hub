# Everything StudentBase's own Terraform used to manage that isn't tied to a specific
# droplet: the CDN, its cert, the Spaces bucket behind it, and mail/SPF/DKIM/icloud
# records. `digitalocean_domain.studentbase`, `prod_api`, `prod_frontend` are in
# dns-studentbase.tf (the routing-relevant records); this file is everything else.
#
# Certificate is DO's own managed Let's Encrypt cert, not the acme provider — DO
# renews it automatically, same as Traefik does for every other cert on this box.
#
# Cleanup still pending: the original uploaded cert from StudentBase's old Terraform
# (`LetsEncryptTerraform8a0ff1bb`) is orphaned at DO, no longer referenced. Delete:
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

# Not the same record as prod_frontend/prod_api in dns-studentbase.tf, the A records
# the apex/api actually resolve to.
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

# Selector name is Postmark's own date-stamp from setup — not a bug, doesn't need updating.
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
