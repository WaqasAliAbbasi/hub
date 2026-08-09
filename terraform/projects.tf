# Keeps DigitalOcean resources that belong to this repo filed under the "Hub"
# project instead of drifting into whatever project happened to be marked
# default at creation time (StudentBase, historically — it predates Hub and is
# still the account's is_default project). digitalocean_project_resources sets
# the *complete* membership list for the project, so every URN that belongs in
# Hub has to be listed here, not just the one being moved — anything left out
# gets silently unassigned back to the default project on the next apply.
data "digitalocean_project" "hub" {
  name = "Hub"
}

# The Terraform state bucket predates every other resource here by definition
# (nothing can be terraform-managed before the backend that stores its own
# state exists), so it's referenced as a data source rather than a resource.
data "digitalocean_spaces_bucket" "tf_state" {
  name   = "personal-hub-terraform-state"
  region = "sgp1"
}

resource "digitalocean_project_resources" "hub" {
  project = data.digitalocean_project.hub.id

  resources = [
    data.digitalocean_domain.main.urn,
    data.digitalocean_spaces_bucket.tf_state.urn,
    digitalocean_spaces_bucket.backups.urn,
  ]
}
