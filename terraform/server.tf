resource "hcloud_ssh_key" "admin" {
  name       = "hub-admin"
  public_key = local.ssh_public_key
}

resource "hcloud_firewall" "hub" {
  name = "hub"

  # Inbound only. Leaving all `direction = "out"` rules unspecified means outbound
  # traffic is unrestricted, which is what we want (image pulls, ACME, backups).
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.ssh_allowed_ips
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # ICMP so the box is pingable for debugging.
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "hub" {
  name  = "hub"
  image = "ubuntu-26.04"
  # cx33 = 4 vCPU / 8 GB (~EUR 8/mo) — leaves headroom for builds and DB restores.
  # (Hetzner's successor to the retired cx32; same memory, more cores.)
  server_type = "cx33"
  # cx* types are EU-only. fsn1 = Falkenstein, Germany.
  location     = "fsn1"
  ssh_keys     = [hcloud_ssh_key.admin.id]
  firewall_ids = [hcloud_firewall.hub.id]

  # Changing user_data replaces the server. That is fine while nothing lives here,
  # but once projects are deployed, change the box by hand and backfill the change
  # into cloud-init.yml rather than letting Terraform rebuild it.
  user_data = templatefile("${path.module}/cloud-init.yml", {
    ssh_public_key = local.ssh_public_key
  })

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  labels = {
    role = "hub"
  }

  lifecycle {
    ignore_changes = [ssh_keys]
  }
}
