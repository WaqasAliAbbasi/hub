# ConfigMap containing the hello world HTML
resource "kubernetes_config_map" "hello_world_html" {
  metadata {
    name      = "hello-world-html"
    namespace = "default"
  }

  data = {
    "index.html" = <<-EOT
      <!DOCTYPE html>
      <html>
      <head>
          <title>Hello World from Kubernetes!</title>
          <style>
              body {
                  font-family: Arial, sans-serif;
                  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                  color: white;
                  text-align: center;
                  padding: 50px;
                  margin: 0;
              }
              .container {
                  background: rgba(255, 255, 255, 0.1);
                  border-radius: 10px;
                  padding: 40px;
                  backdrop-filter: blur(10px);
                  border: 1px solid rgba(255, 255, 255, 0.1);
                  max-width: 600px;
                  margin: 0 auto;
              }
              h1 { font-size: 3em; margin-bottom: 20px; }
              p { font-size: 1.2em; margin-bottom: 10px; }
              .emoji { font-size: 2em; }
              .info { background: rgba(255, 255, 255, 0.1); padding: 20px; border-radius: 5px; margin-top: 30px; }
          </style>
      </head>
      <body>
          <div class="container">
              <h1>Hello World! <span class="emoji">🚀</span></h1>
              <p>Welcome to your Kubernetes deployment!</p>
              <p>This app is running on a K3s cluster managed by Terraform.</p>
              
              <div class="info">
                  <h3>Deployment Details</h3>
                  <p><strong>Platform:</strong> Kubernetes (K3s)</p>
                  <p><strong>Infrastructure:</strong> DigitalOcean</p>
                  <p><strong>Managed by:</strong> Terraform</p>
                  <p><strong>Container:</strong> nginx:alpine</p>
              </div>
              
              <p style="margin-top: 30px; opacity: 0.8;">
                  Pod hostname: <span id="hostname"></span>
              </p>
          </div>
          
          <script>
              // Display the hostname to show which pod is serving the request
              document.getElementById('hostname').textContent = window.location.hostname;
          </script>
      </body>
      </html>
    EOT
  }
}

# Create the hello world deployment
resource "kubernetes_deployment" "hello_world" {
  metadata {
    name      = "hello-world"
    namespace = "default"
    labels = {
      app = "hello-world"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "hello-world"
      }
    }

    template {
      metadata {
        labels = {
          app = "hello-world"
        }
      }

      spec {
        container {
          image = "nginx:alpine"
          name  = "hello-world"

          port {
            container_port = 80
          }

          # Custom HTML content
          volume_mount {
            name       = "html-content"
            mount_path = "/usr/share/nginx/html"
          }

          resources {
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
            requests = {
              cpu    = "50m"
              memory = "32Mi"
            }
          }
        }

        volume {
          name = "html-content"
          config_map {
            name = kubernetes_config_map.hello_world_html.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_config_map.hello_world_html]
}

# Create a service to expose the deployment
resource "kubernetes_service" "hello_world" {
  metadata {
    name      = "hello-world-service"
    namespace = "default"
    labels = {
      app = "hello-world"
    }
  }

  spec {
    selector = {
      app = "hello-world"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment.hello_world]
}

# Create an ingress to expose the service externally
resource "kubernetes_ingress_v1" "hello_world" {
  metadata {
    name      = "hello-world-ingress"
    namespace = "default"
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints"      = "web,websecure"
      "traefik.ingress.kubernetes.io/router.tls.certresolver" = "letsencrypt"
    }
  }

  spec {
    ingress_class_name = "traefik"

    tls {
      hosts       = ["hub.${var.domain}"]
    }

    rule {
      host = "hub.${var.domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.hello_world.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_service.hello_world]
}