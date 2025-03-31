terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.0.0-pre2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.36.0"
    }
  }
}

provider "kubernetes" {
  host                   = var.kubernetes_host
  client_certificate     = var.client_certificate
  client_key             = var.client_key
  cluster_ca_certificate = var.cluster_ca_certificate
}

provider "helm" {
  kubernetes = {
    host                   = var.kubernetes_host
    client_certificate     = var.client_certificate
    client_key             = var.client_key
    cluster_ca_certificate = var.cluster_ca_certificate
  }
}
