# Backups get their own bucket and their own scoped credential — deliberately not
# reusing the Spaces key that authenticates the Terraform state backend. A leaked
# backup credential should not also be a path to tampering with state.
resource "digitalocean_spaces_bucket" "backups" {
  name   = "personal-hub-backups"
  region = "sgp1"

  # Terraform must not be the thing that can delete backups. Emptying the bucket
  # (if it's ever actually decommissioned) is a deliberate, separate action.
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
  description = "Scoped Spaces key for the backup job — write this into stacks/backup/.env by hand, it is not synced automatically"
  value       = digitalocean_spaces_key.backup.access_key
  sensitive   = true
}

output "backup_secret_access_key" {
  value     = digitalocean_spaces_key.backup.secret_key
  sensitive = true
}
