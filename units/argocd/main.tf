locals {
  app_projects = concat(
    [
      {
        name        = "payments-app"
        description = "Payments application project"
        namespace   = "payments-app"
      }
    ],
    var.enable_consul_project ? [
      {
        name        = "consul"
        description = "Consul service mesh project"
        namespace   = "consul"
      }
    ] : []
  )
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "9.5.7"
  namespace        = "argocd"
  create_namespace = true

  values = [yamlencode({
    server = {
      service = {
        type = var.service_type
      }
      additionalProjects = [for p in local.app_projects : {
        name        = p.name
        namespace   = "argocd"
        description = p.description
        sourceRepos = ["*"]
        destinations = [{
          server    = "https://kubernetes.default.svc"
          namespace = p.namespace
        }]
        clusterResourceWhitelist = [{
          group = "*"
          kind  = "*"
        }]
      }]
    }
    configs = {
      params = {
        "server.insecure" = true
      }
    }
  })]
}
