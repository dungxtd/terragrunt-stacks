resource "helm_release" "flagger" {
  name             = "flagger"
  repository       = "https://flagger.app"
  chart            = "flagger"
  version          = "1.42.0"
  namespace        = "flagger-system"
  create_namespace = true

  values = [yamlencode({
    meshProvider = var.mesh_provider
    metricsServer = var.metrics_server
  })]
}

resource "helm_release" "flagger_loadtester" {
  count = var.enable_loadtester ? 1 : 0

  name             = "flagger-loadtester"
  repository       = "https://flagger.app"
  chart            = "loadtester"
  version          = "0.34.0"
  namespace        = "flagger-system"
  create_namespace = true

  depends_on = [helm_release.flagger]
}
