# Create the FreshRSS StatefulSet
resource "kubernetes_stateful_set" "freshrss" {
  metadata {
    name      = "freshrss"
    namespace = "default"
    labels = {
      app = "freshrss"
    }
  }

  spec {
    replicas     = 1
    service_name = "freshrss-service"

    selector {
      match_labels = {
        app = "freshrss"
      }
    }

    template {
      metadata {
        labels = {
          app = "freshrss"
        }
      }

      spec {
        container {
          image = "freshrss/freshrss:latest"
          name  = "freshrss"

          port {
            container_port = 80
          }

          env {
            name  = "CRON_MIN"
            value = "1,31"
          }

          env {
            name  = "TZ"
            value = "UTC"
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }

          # Persistent storage for FreshRSS data
          volume_mount {
            name       = "freshrss-data"
            mount_path = "/var/www/FreshRSS/data"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "freshrss-data"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "5Gi"
          }
        }
      }
    }
  }
}

# Create a service to expose the StatefulSet
resource "kubernetes_service" "freshrss" {
  metadata {
    name      = "freshrss-service"
    namespace = "default"
    labels = {
      app = "freshrss"
    }
  }

  spec {
    selector = {
      app = "freshrss"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_stateful_set.freshrss]
}

# Create an ingress to expose the service externally
resource "kubernetes_ingress_v1" "freshrss" {
  metadata {
    name      = "freshrss-ingress"
    namespace = "default"
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints"      = "web,websecure"
      "traefik.ingress.kubernetes.io/router.tls.certresolver" = "letsencrypt"
    }
  }

  spec {
    ingress_class_name = "traefik"

    tls {
      hosts = ["hub.${var.domain}"]
    }

    rule {
      host = "hub.${var.domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.freshrss.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_service.freshrss]
}