resource "helm_release" "linkerd_crds" {
  name             = "linkerd-crds"
  repository       = "https://helm.linkerd.io/edge"
  chart            = "linkerd-crds"
  version          = "2026.4.3"
  namespace        = "linkerd"
  create_namespace = true
  timeout          = 600
  cleanup_on_fail  = true
}

resource "tls_private_key" "trust_anchor" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "trust_anchor" {
  private_key_pem = tls_private_key.trust_anchor.private_key_pem

  subject {
    common_name = "root.linkerd.cluster.local"
  }

  validity_period_hours = 87600
  is_ca_certificate     = true

  allowed_uses = ["cert_signing", "crl_signing"]
}

resource "tls_private_key" "issuer" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "issuer" {
  private_key_pem = tls_private_key.issuer.private_key_pem

  subject {
    common_name = "identity.linkerd.cluster.local"
  }
}

resource "tls_locally_signed_cert" "issuer" {
  cert_request_pem   = tls_cert_request.issuer.cert_request_pem
  ca_private_key_pem = tls_private_key.trust_anchor.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.trust_anchor.cert_pem

  validity_period_hours = 8760
  is_ca_certificate     = true

  allowed_uses = ["cert_signing", "crl_signing"]
}

resource "helm_release" "linkerd_control_plane" {
  name            = "linkerd-control-plane"
  repository      = "https://helm.linkerd.io/edge"
  chart           = "linkerd-control-plane"
  version         = "2026.4.3"
  namespace       = "linkerd"
  timeout         = 600
  cleanup_on_fail = true

  values = [yamlencode({
    identityTrustAnchorsPEM = tls_self_signed_cert.trust_anchor.cert_pem
    identity = {
      issuer = {
        tls = {
          crtPEM = tls_locally_signed_cert.issuer.cert_pem
          keyPEM = tls_private_key.issuer.private_key_pem
        }
      }
    }
  })]

  depends_on = [helm_release.linkerd_crds]
}

resource "helm_release" "linkerd_viz" {
  count = var.enable_viz ? 1 : 0

  name             = "linkerd-viz"
  repository       = "https://helm.linkerd.io/edge"
  chart            = "linkerd-viz"
  version          = "2026.4.3"
  namespace        = "linkerd-viz"
  create_namespace = true
  timeout          = 600
  cleanup_on_fail  = true

  values = [yamlencode({
    dashboard = { enforcedHostRegexp = ".+" }
  })]

  depends_on = [helm_release.linkerd_control_plane]
}
