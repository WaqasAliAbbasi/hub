resource "helm_release" "traefik" {
  depends_on       = [kubectl_manifest.cilium_load_balancer_ip_pool]
  name             = "traefik"
  repository       = "https://traefik.github.io/charts/"
  chart            = "traefik"
  create_namespace = true
  namespace        = "traefik"
  atomic           = true
  cleanup_on_fail  = true
}
