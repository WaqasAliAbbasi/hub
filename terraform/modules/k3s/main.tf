terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.50.0"
    }
    # To create random password
    random = {
      source  = "hashicorp/random"
      version = "3.7.1"
    }
    # To setup VMs https://cloudinit.readthedocs.io/en/latest/reference/examples.html
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.7-alpha.2"
    }
    remote = {
      source  = "tenstad/remote"
      version = "0.1.3"
    }
  }
}


provider "digitalocean" {
  token = var.digitalocean_token
}
