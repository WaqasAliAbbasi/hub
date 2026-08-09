# Own bucket, own scoped credential — separate from the state backend's Spaces key,
# so a leaked backup credential can't also tamper with state.
resource "digitalocean_spaces_bucket" "backups" {
  name   = "personal-hub-backups"
  region = "sgp1"

  # Terraform must never be able to delete backups.
  force_destroy = false

  # The box holds a readwrite key to this bucket, so anyone with root there (a
  # container escape, a leaked CI key) could `restic forget` every snapshot along
  # with the live data. Versioning keeps deleted objects recoverable as noncurrent
  # versions for 30 days — a restic-level wipe becomes a detectable event with a
  # recovery window instead of a total loss. The expiry also bounds the storage
  # that restic's own weekly prune would otherwise accumulate forever.
  #
  # Residual risk: the same key can still delete versions one by one via the S3
  # API directly; Spaces has no object-lock to prevent that.
  versioning {
    enabled = true
  }

  lifecycle_rule {
    id      = "expire-noncurrent-versions"
    enabled = true

    noncurrent_version_expiration {
      days = 30
    }
  }
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
