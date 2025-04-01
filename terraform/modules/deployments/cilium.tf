resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.15.6"
  namespace  = "kube-system"


  set = [{
    name  = "ipam.mode"
    value = "kubernetes"
    },

    {
      name  = "kubeProxyReplacement"
      value = "false"
    }

    , {
      name  = "securityContext.capabilities.ciliumAgent"
      value = "{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}"
    }

    , {
      name  = "securityContext.capabilities.cleanCiliumState"
      value = "{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}"
    }

    , {
      name  = "cgroup.autoMount.enabled"
      value = "false"
    }

    , {
      name  = "cgroup.hostRoot"
      value = "/sys/fs/cgroup"
  }]
}

resource "kubernetes_manifest" "cilium_loadbalancer_ip_pool" {
  depends_on = [helm_release.cilium]
  manifest = {
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumLoadBalancerIPPool"
    metadata = {
      name = "blue-pool"
    }
    spec = {
      blocks = [
        {
          start = var.host_ip_address
        }
      ]
    }
  }
}