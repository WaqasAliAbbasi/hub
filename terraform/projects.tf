# Files this repo's DO resources under the "Hub" project instead of the account
# default. digitalocean_project_resources sets the *complete* membership list —
# anything left out gets silently unassigned back to default on the next apply.
data "digitalocean_project" "hub" {
  name = "Hub"
}

# Predates everything else here (it's the backend that stores this state), so a
# data source rather than a resource.
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
