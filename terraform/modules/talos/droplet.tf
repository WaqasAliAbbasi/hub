## Upload a custom image to DigitalOcean
resource "digitalocean_custom_image" "talos_custom_image" {
  name         = "talos-linux-${var.talos_version}"
  url          = "https://factory.talos.dev/image/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba/v${var.talos_version}/digital-ocean-amd64.raw.gz"
  distribution = "Unknown OS"
  regions      = ["${var.do_region}"]
}

## Cheese the creation of an SSH key
resource "tls_private_key" "fake_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "digitalocean_ssh_key" "fake_ssh_key" {
  name       = "${var.cluster_name}-fake-ssh-key"
  public_key = tls_private_key.fake_ssh_key.public_key_openssh
}

## Create all instances
resource "digitalocean_droplet" "talos_control_plane" {
  image    = digitalocean_custom_image.talos_custom_image.id
  name     = "${var.cluster_name}-control-plane"
  region   = var.do_region
  size     = var.do_plan_control_plane
  ssh_keys = [digitalocean_ssh_key.fake_ssh_key.id]
}

resource "talos_machine_secrets" "machine_secrets" {}

data "talos_client_configuration" "talosconfig" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  endpoints            = [digitalocean_droplet.talos_control_plane.ipv4_address]
}

data "talos_machine_configuration" "machineconfig_cp" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${digitalocean_droplet.talos_control_plane.ipv4_address}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
  depends_on       = [digitalocean_droplet.talos_control_plane]
  talos_version    = var.talos_version
  config_patches = [
    file("${path.module}/files/machine-config.yaml"),
  ]
}

resource "talos_machine_configuration_apply" "cp_config_apply" {
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_cp.machine_configuration
  node                        = digitalocean_droplet.talos_control_plane.ipv4_address
  timeouts = {
    create = "1m"
  }
}

resource "talos_machine_bootstrap" "bootstrap" {
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = digitalocean_droplet.talos_control_plane.ipv4_address
  timeouts = {
    create = "1m"
  }
}

resource "talos_cluster_kubeconfig" "kubeconfig" {
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = digitalocean_droplet.talos_control_plane.ipv4_address
}
