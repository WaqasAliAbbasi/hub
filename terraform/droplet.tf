# SSH Key for the droplet
resource "digitalocean_ssh_key" "hub" {
  name       = "hub-k3s-key"
  public_key = var.ssh_public_key != "" ? var.ssh_public_key : file(pathexpand("~/.ssh/id_rsa.pub"))
}

# K3s cluster droplet
resource "digitalocean_droplet" "k3s_cluster" {
  image    = "ubuntu-22-04-x64"
  name     = "hub-k3s-cluster"
  region   = var.region
  size     = var.droplet_size
  ssh_keys = [digitalocean_ssh_key.hub.fingerprint]

  # Cloud-init configuration for K3s installation
  user_data = file("${path.module}/cloud-init.yml")

  # Enable monitoring and backups
  monitoring = true
  backups    = false

  tags = ["k3s", "hub", "kubernetes"]
}

# Assign droplet to the Hub project
resource "digitalocean_project_resources" "hub_resources" {
  project = data.digitalocean_project.hub.id
  resources = [
    digitalocean_droplet.k3s_cluster.urn
  ]
}

# Data source to get kubeconfig after droplet is ready
data "external" "kubeconfig" {
  program = ["bash", "-c", <<-EOT
    # Wait for droplet to be ready and K3s to be installed
    max_attempts=60
    attempt=1
    
    while [ $attempt -le $max_attempts ]; do
      if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@${digitalocean_droplet.k3s_cluster.ipv4_address} "test -f /etc/rancher/k3s/k3s.yaml" 2>/dev/null; then
        # Get the kubeconfig
        kubeconfig=$(ssh -o StrictHostKeyChecking=no root@${digitalocean_droplet.k3s_cluster.ipv4_address} "cat /etc/rancher/k3s/k3s.yaml" 2>/dev/null | sed "s/127.0.0.1/${digitalocean_droplet.k3s_cluster.ipv4_address}/g")
        
        # Extract server, token, and ca certificate
        server=$(echo "$kubeconfig" | grep "server:" | awk '{print $2}')
        ca_cert=$(echo "$kubeconfig" | grep "certificate-authority-data:" | awk '{print $2}')
        
        # Get token from the cluster
        token=$(ssh -o StrictHostKeyChecking=no root@${digitalocean_droplet.k3s_cluster.ipv4_address} "cat /var/lib/rancher/k3s/server/token" 2>/dev/null)
        
        # Output JSON
        echo "{\"kubeconfig\":\"$(echo "$kubeconfig" | base64 -w 0)\"}"
        exit 0
      fi
      
      echo "Waiting for K3s to be ready... (attempt $attempt/$max_attempts)" >&2
      sleep 10
      attempt=$((attempt + 1))
    done
    
    echo "Timeout waiting for K3s to be ready" >&2
    exit 1
  EOT
  ]

  depends_on = [digitalocean_droplet.k3s_cluster]
}