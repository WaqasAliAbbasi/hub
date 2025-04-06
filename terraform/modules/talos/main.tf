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
    null = {
      source  = "hashicorp/null"
      version = "3.2.4-alpha.2"
    }
  }
}


provider "digitalocean" {
  token = var.digitalocean_token
}

data "digitalocean_project" "hub" {
  name = "Hub"
}

resource "digitalocean_project_resources" "hub_resources" {
  project = data.digitalocean_project.hub.id
  resources = [
    digitalocean_droplet.talos_control_plane.urn
  ]
}
