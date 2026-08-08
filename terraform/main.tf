terraform {
  # State lives in DigitalOcean Spaces. The s3 backend reads AWS_ACCESS_KEY_ID /
  # AWS_SECRET_ACCESS_KEY natively, so no -backend-config flags are needed — the
  # Makefile supplies them (along with every TF_VAR_*) from
  # terraform/secrets.enc.env. Run terraform via `make`, not directly.
  #
  # NOTE: this uses a different key from the abandoned K3s attempt
  # (terraform-server.tfstate). That state may still reference a droplet and DNS
  # records; check the DigitalOcean console for leftovers and remove them by hand.
  backend "s3" {
    endpoints = {
      s3 = "https://sgp1.digitaloceanspaces.com"
    }
    bucket                      = "personal-hub-terraform-state"
    key                         = "hub.tfstate"
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    region                      = "us-east-1"
  }

  required_version = ">= 1.9"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.68"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.50"
    }
  }
}

# Compute lives on Hetzner.
provider "hcloud" {
  token = var.hcloud_token
}

# DigitalOcean is retained only for DNS (waqasali.dev is delegated there) and for
# the Spaces buckets holding state and backups. No compute.
provider "digitalocean" {
  token = var.digitalocean_token

  # Spaces (S3-compatible) operations go through a separate credential from the
  # DO API token above — this is what lets the provider create the backup bucket
  # and the scoped key that reads/writes it.
  spaces_access_id  = var.spaces_access_id
  spaces_secret_key = var.spaces_secret_key
}

locals {
  ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : file(pathexpand("~/.ssh/id_rsa.pub"))
}
