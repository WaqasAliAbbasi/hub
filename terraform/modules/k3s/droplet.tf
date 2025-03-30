resource "random_password" "hub_01_password" {
  length      = 16
  min_upper   = 1
  min_numeric = 1
}


data "cloudinit_config" "k3s_virtual_machine_cloud_config" {
  gzip          = false
  base64_encode = false

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = templatefile("${path.module}/cloud-config.yaml.tftpl", {
      root_password = random_password.hub_01_password.result
    })
  }
}

resource "digitalocean_droplet" "hub_01" {
  image      = "ubuntu-24-10-x64"
  name       = "hub-01"
  region     = "sgp1"
  size       = "s-1vcpu-2gb"
  backups    = false
  monitoring = true
  user_data  = data.cloudinit_config.k3s_virtual_machine_cloud_config.rendered
  connection {
    host     = digitalocean_droplet.hub_01.ipv4_address
    user     = "root"
    password = random_password.hub_01_password.result
  }
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait || true"
    ]
  }
}

data "remote_file" "k3s_config" {
  conn {
    host     = digitalocean_droplet.hub_01.ipv4_address
    user     = "root"
    password = random_password.hub_01_password.result
  }

  path = "/etc/rancher/k3s/k3s.yaml"
}
