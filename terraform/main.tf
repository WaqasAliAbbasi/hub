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
}

variable "digitalocean_token" {}
