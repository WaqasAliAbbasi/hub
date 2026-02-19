variable "digitalocean_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "sgp1"
}

variable "droplet_size" {
  description = "DigitalOcean droplet size"
  type        = string
  default     = "s-1vcpu-2gb"
}

variable "domain" {
  description = "Domain name for the cluster"
  type        = string
  default     = "waqasali.dev"
}

variable "ssh_public_key" {
  description = "SSH public key for the droplet"
  type        = string
  default     = ""
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt ACME notifications"
  type        = string
  default     = "waqas.abbasi@outlook.com"
}