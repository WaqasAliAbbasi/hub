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

# Everything below was already sitting on the domain at DO, created by hand over the
# years — GitHub Pages (apex + www), iCloud Mail, and a couple of one-off site
# verification TXT records. Imported 2026-08-09 so the whole domain is under
# Terraform, not just the wildcard. Import commands, run once after adding each
# resource below:
#
#   terraform import 'digitalocean_record.apex_github["185.199.109.153"]' waqasali.dev,1809246569
#   terraform import 'digitalocean_record.apex_github["185.199.108.153"]' waqasali.dev,1809246597
#   terraform import 'digitalocean_record.apex_github["185.199.110.153"]' waqasali.dev,1809247086
#   terraform import 'digitalocean_record.apex_github["185.199.111.153"]' waqasali.dev,1809247090
#   terraform import 'digitalocean_record.apex_github_v6["2606:50c0:8000::153"]' waqasali.dev,1809250197
#   terraform import 'digitalocean_record.apex_github_v6["2606:50c0:8001::153"]' waqasali.dev,1809250209
#   terraform import 'digitalocean_record.apex_github_v6["2606:50c0:8003::153"]' waqasali.dev,1809250229
#   terraform import 'digitalocean_record.apex_github_v6["2606:50c0:8002::153"]' waqasali.dev,1809250265
#   terraform import digitalocean_record.www waqasali.dev,1809246682
#   terraform import digitalocean_record.icloud_dkim waqasali.dev,1809246652
#   terraform import 'digitalocean_record.icloud_mx["mx01.mail.icloud.com."]' waqasali.dev,1809246759
#   terraform import 'digitalocean_record.icloud_mx["mx02.mail.icloud.com."]' waqasali.dev,1809246744
#   terraform import digitalocean_record.spf waqasali.dev,1809246781
#   terraform import digitalocean_record.apple_domain_verification waqasali.dev,1809246813
#   terraform import digitalocean_record.google_site_verification waqasali.dev,1809246823
#
# `terraform plan` should come back clean once every import above succeeds —
# anything else means an import targeted the wrong record.

resource "digitalocean_record" "apex_github" {
  for_each = toset(["185.199.108.153", "185.199.109.153", "185.199.110.153", "185.199.111.153"])

  domain = data.digitalocean_domain.main.id
  type   = "A"
  name   = "@"
  value  = each.key
  ttl    = 3600
}

resource "digitalocean_record" "apex_github_v6" {
  for_each = toset(["2606:50c0:8000::153", "2606:50c0:8001::153", "2606:50c0:8002::153", "2606:50c0:8003::153"])

  domain = data.digitalocean_domain.main.id
  type   = "AAAA"
  name   = "@"
  value  = each.key
  ttl    = 3600
}

resource "digitalocean_record" "www" {
  domain = data.digitalocean_domain.main.id
  type   = "CNAME"
  name   = "www"
  value  = "waqasaliabbasi.github.io."
  ttl    = 3600
}

resource "digitalocean_record" "icloud_dkim" {
  domain = data.digitalocean_domain.main.id
  type   = "CNAME"
  name   = "sig1._domainkey"
  value  = "sig1.dkim.waqasali.dev.at.icloudmailadmin.com."
  ttl    = 3600
}

resource "digitalocean_record" "icloud_mx" {
  for_each = toset(["mx01.mail.icloud.com.", "mx02.mail.icloud.com."])

  domain   = data.digitalocean_domain.main.id
  type     = "MX"
  name     = "@"
  value    = each.key
  priority = 10
  ttl      = 3600
}

resource "digitalocean_record" "spf" {
  domain = data.digitalocean_domain.main.id
  type   = "TXT"
  name   = "@"
  value  = "v=spf1 include:icloud.com ~all"
  ttl    = 3600
}

resource "digitalocean_record" "apple_domain_verification" {
  domain = data.digitalocean_domain.main.id
  type   = "TXT"
  name   = "@"
  value  = "apple-domain=TH97n1fMcVZQFEXG"
  ttl    = 3600
}

resource "digitalocean_record" "google_site_verification" {
  domain = data.digitalocean_domain.main.id
  type   = "TXT"
  name   = "@"
  value  = "google-site-verification=j6G9-FAl3n6JmGADsWVJjzPHiUaiaibaz8ydiIHKQxc"
  ttl    = 3600
}
