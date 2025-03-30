resource "kubernetes_service_account" "cluster_admin" {
  metadata {
    name      = "admin-user"
    namespace = "default"
  }
}

resource "kubernetes_cluster_role_binding" "cluster_admin_role_binding" {
  metadata {
    name = "admin-user"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.cluster_admin.metadata.0.name
    namespace = "default"
  }
}

resource "kubernetes_secret" "cluster_admin_token" {
  metadata {
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.cluster_admin.metadata.0.name
    }

    generate_name = "${kubernetes_service_account.cluster_admin.metadata.0.name}-"
  }

  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}
