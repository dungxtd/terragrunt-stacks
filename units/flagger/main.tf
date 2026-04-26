resource "helm_release" "flagger" {
  name             = "flagger"
  repository       = "https://flagger.app"
  chart            = "flagger"
  namespace        = "flagger-system"
  create_namespace = true

  set {
    name  = "meshProvider"
    value = var.mesh_provider
  }

  set {
    name  = "metricsServer"
    value = var.metrics_server
  }
}

resource "helm_release" "flagger_loadtester" {
  count = var.enable_loadtester ? 1 : 0

  name             = "flagger-loadtester"
  repository       = "https://flagger.app"
  chart            = "loadtester"
  namespace        = "flagger-system"
  create_namespace = true

  depends_on = [helm_release.flagger]
}
