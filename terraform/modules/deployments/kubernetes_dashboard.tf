resource "helm_release" "kubernetes_dashboard" {
  name             = "kubernetes-dashboard"
  repository       = "https://kubernetes.github.io/dashboard/"
  chart            = "kubernetes-dashboard"
  create_namespace = true
  namespace        = "default"
  atomic           = true
  cleanup_on_fail  = true
}
