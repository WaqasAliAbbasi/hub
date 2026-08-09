resource "hcloud_ssh_key" "admin" {
  name       = "hub-admin"
  public_key = local.ssh_public_key
}

resource "hcloud_firewall" "hub" {
  name = "hub"

  # Inbound only — no `out` rules means outbound stays unrestricted (image pulls, ACME, backups).
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

  # ICMP so the box is pingable.
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "hub" {
  name  = "hub"
  image = "ubuntu-26.04"
  # 4 vCPU / 8 GB (~EUR 8/mo) — headroom for builds and DB restores.
  server_type  = "cx33"
  location     = "fsn1" # cx* types are EU-only
  ssh_keys     = [hcloud_ssh_key.admin.id]
  firewall_ids = [hcloud_firewall.hub.id]

  # Changing user_data replaces the server; prevent_destroy below turns that into
  # a loud error instead. Change the box by hand and backfill into cloud-init.yml.
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

    # Errors on any replacement (image, server_type, user_data). To genuinely replace
    # the box: comment this out, and read docs/disaster-recovery.md first.
    prevent_destroy = true
  }
}
