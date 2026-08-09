# Own bucket, own scoped credential — separate from the state backend's Spaces key,
# so a leaked backup credential can't also tamper with state.
resource "digitalocean_spaces_bucket" "backups" {
  name   = "personal-hub-backups"
  region = "sgp1"

  # Terraform must never be able to delete backups.
  force_destroy = false
}

resource "digitalocean_spaces_key" "backup" {
  name = "hub-backup"

  grant {
    bucket     = digitalocean_spaces_bucket.backups.name
    permission = "readwrite"
  }
}

output "backup_bucket" {
  description = "Spaces bucket restic backs up to"
  value       = digitalocean_spaces_bucket.backups.name
}

output "backup_access_key_id" {
  description = "Scoped Spaces key for the backup job — write into stacks/backup/.env by hand, not synced automatically"
  value       = digitalocean_spaces_key.backup.access_key
  sensitive   = true
}

output "backup_secret_access_key" {
  value     = digitalocean_spaces_key.backup.secret_key
  sensitive = true
}
