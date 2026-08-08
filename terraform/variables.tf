variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "digitalocean_token" {
  description = "DigitalOcean API token (DNS only)"
  type        = string
  sensitive   = true
}

variable "spaces_access_id" {
  description = <<-EOT
    Spaces access key ID, for provider-level Spaces operations (creating buckets
    and scoped keys). This is the *account-level* Spaces key already used for the
    Terraform state backend, not the scoped backup key backup.tf creates from it —
    that one can't bootstrap itself.
  EOT
  type        = string
  sensitive   = true
}

variable "spaces_secret_key" {
  description = "Spaces secret key matching spaces_access_id."
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key for the deploy user. Empty falls back to ~/.ssh/id_rsa.pub."
  type        = string
  default     = ""
}

variable "ssh_allowed_ips" {
  description = <<-EOT
    CIDRs permitted to reach port 22. Defaults to open, which is acceptable given
    key-only auth plus fail2ban; narrow to your home IP if that address is stable.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}
