terraform {
  # State in DigitalOcean Spaces. The s3 backend reads AWS_ACCESS_KEY_ID/SECRET_ACCESS_KEY
  # natively, supplied by the Makefile from terraform/secrets.enc.env — run via `make`, not
  # directly. Different key from the abandoned K3s attempt (terraform-server.tfstate).
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

provider "hcloud" {
  token = var.hcloud_token
}

# DNS + Spaces (state, backups) only. No compute.
provider "digitalocean" {
  token = var.digitalocean_token

  # Separate credential from the DO API token — needed for Spaces (S3-compatible) ops.
  spaces_access_id  = var.spaces_access_id
  spaces_secret_key = var.spaces_secret_key
}

locals {
  ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : file(pathexpand("~/.ssh/id_rsa.pub"))
}
