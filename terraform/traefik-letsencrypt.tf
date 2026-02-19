# HelmChartConfig to configure K3s Traefik with Let's Encrypt ACME (Production)
resource "kubernetes_manifest" "traefik_letsencrypt_config" {
  manifest = {
    apiVersion = "helm.cattle.io/v1"
    kind       = "HelmChartConfig"
    metadata = {
      name      = "traefik"
      namespace = "kube-system"
    }
    spec = {
      valuesContent = <<-EOT
        # Traefik additional arguments for Let's Encrypt ACME (Production)
        additionalArguments:
          - "--certificatesresolvers.letsencrypt.acme.email=${var.letsencrypt_email}"
          - "--certificatesresolvers.letsencrypt.acme.storage=/data/acme.json"
          - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
          - "--certificatesresolvers.letsencrypt.acme.caserver=https://acme-v02.api.letsencrypt.org/directory"
          - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
          - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
        
        # Persistence for ACME certificates
        persistence:
          enabled: true
          size: "128Mi"
        
        # Ensure proper resource limits for production
        resources:
          requests:
            cpu: "100m"
            memory: "50Mi"
          limits:
            cpu: "300m"
            memory: "150Mi"
      EOT
    }
  }

  depends_on = [
    data.external.kubeconfig
  ]
}