resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts/"
  chart            = "traefik"
  create_namespace = true
  namespace        = "traefik"
  atomic           = true
  cleanup_on_fail  = true
  depends_on       = [kubernetes_manifest.cilium_loadbalancer_ip_pool]
}
