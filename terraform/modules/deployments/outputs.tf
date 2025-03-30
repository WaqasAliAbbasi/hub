output "admin_user_service_account_token" {
  value     = kubernetes_secret.cluster_admin_token.data.token
  sensitive = true
}
