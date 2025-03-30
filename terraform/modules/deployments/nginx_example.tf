resource "kubernetes_service" "example" {
  metadata {
    name = "terraform-example"
  }
  spec {
    selector = {
      app = kubernetes_pod.example.metadata.0.labels.app
    }
    port {
      port        = 8080
      target_port = 80
    }
  }
}

resource "kubernetes_pod" "example" {
  metadata {
    name = "terraform-example"
    labels = {
      app = "MyApp"
    }
  }

  spec {
    container {
      image = "nginx:1.21.6"
      name  = "example"
    }
  }
}

resource "kubernetes_ingress_v1" "example" {
  metadata {
    name = "example"
  }
  spec {
    rule {
      host = "example.com"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.example.metadata.0.name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
}
