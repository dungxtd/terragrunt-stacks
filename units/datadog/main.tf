resource "helm_release" "datadog" {
  name             = "datadog"
  repository       = "https://helm.datadoghq.com"
  chart            = "datadog"
  version          = "3.202.1"
  namespace        = "datadog"
  create_namespace = true

  values = [yamlencode({
    datadog = {
      apiKey       = var.datadog_api_key
      site         = var.datadog_site
      logs         = { enabled = true }
      apm          = { portEnabled = true }
      processAgent = { enabled = true }
    }
  })]
}
