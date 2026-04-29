resource "helm_release" "consul" {
  name             = "consul"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "consul"
  version          = "1.6.3"
  namespace        = "consul"
  create_namespace = true

  values = [yamlencode({
    global = {
      name       = "consul"
      datacenter = var.datacenter
      acls = {
        manageSystemACLs = true
      }
      tls = {
        enabled = true
      }
      metrics = {
        enabled            = true
        enableAgentMetrics = true
      }
    }

    server = {
      enabled  = true
      replicas = var.replicas
      storage  = "10Gi"
    }

    client = {
      enabled = true
    }

    connectInject = {
      enabled = true
      default = true
      transparentProxy = {
        defaultEnabled = true
      }
    }

    apiGateway = {
      enabled = true
      managedGatewayClass = {
        serviceType = "LoadBalancer"
      }
    }

    terminatingGateways = {
      enabled = true
      defaults = {
        replicas = 1
      }
      gateways = [{
        name = "terminating-gateway"
      }]
    }

    meshGateway = {
      enabled = false
    }

    ui = {
      enabled = true
      service = {
        type = "LoadBalancer"
      }
    }
  })]
}
