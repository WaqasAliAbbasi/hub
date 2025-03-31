variable "digitalocean_token" {}
variable "do_region" {
  default = "sgp1"
}
variable "cluster_name" {
  default = "hub-cluster"
}
variable "do_plan_control_plane" {
  default = "s-1vcpu-2gb"
}
