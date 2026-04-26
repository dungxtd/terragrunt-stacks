resource "helm_release" "linkerd_crds" {
  name             = "linkerd-crds"
  repository       = "https://helm.linkerd.io/edge"
  chart            = "linkerd-crds"
  namespace        = "linkerd"
  create_namespace = true
}

resource "helm_release" "linkerd_control_plane" {
  name       = "linkerd-control-plane"
  repository = "https://helm.linkerd.io/edge"
  chart      = "linkerd-control-plane"
  namespace  = "linkerd"

  set {
    name  = "identity.externalCA"
    value = var.external_ca
  }

  set {
    name  = "identity.issuer.scheme"
    value = "kubernetes.io/tls"
  }

  depends_on = [helm_release.linkerd_crds]
}

resource "helm_release" "linkerd_viz" {
  count = var.enable_viz ? 1 : 0

  name             = "linkerd-viz"
  repository       = "https://helm.linkerd.io/edge"
  chart            = "linkerd-viz"
  namespace        = "linkerd-viz"
  create_namespace = true

  depends_on = [helm_release.linkerd_control_plane]
}
