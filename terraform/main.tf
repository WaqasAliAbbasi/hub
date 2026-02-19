terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://sgp1.digitaloceanspaces.com"
    }
    bucket                      = "personal-hub-terraform-state"
    key                         = "terraform-server.tfstate"
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    region                      = "us-east-1"
  }

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.50"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }
}

provider "digitalocean" {
  token = var.digitalocean_token
}

# Get existing DigitalOcean project
data "digitalocean_project" "hub" {
  name = "Hub"
}

locals {
  kube_config = yamldecode(base64decode(data.external.kubeconfig.result.kubeconfig))
}

provider "kubernetes" {
  host                   = local.kube_config.clusters[0].cluster.server
  client_certificate     = base64decode(local.kube_config.users[0].user["client-certificate-data"])
  client_key             = base64decode(local.kube_config.users[0].user["client-key-data"])
  cluster_ca_certificate = base64decode(local.kube_config.clusters[0].cluster["certificate-authority-data"])
}