terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.50.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.6"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.7.1"
    }
  }
}


provider "digitalocean" {
  token = var.digitalocean_token
}
