resource "helm_release" "linkerd_crds" {
  name             = "linkerd-crds"
  repository       = "https://helm.linkerd.io/edge"
  chart            = "linkerd-crds"
  namespace        = "linkerd"
  create_namespace = true
  timeout          = 600
}

resource "tls_private_key" "trust_anchor" {
  count       = var.external_ca ? 0 : 1
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "trust_anchor" {
  count           = var.external_ca ? 0 : 1
  private_key_pem = tls_private_key.trust_anchor[0].private_key_pem

  subject {
    common_name = "root.linkerd.cluster.local"
  }

  validity_period_hours = 87600
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

resource "tls_private_key" "issuer" {
  count       = var.external_ca ? 0 : 1
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "issuer" {
  count           = var.external_ca ? 0 : 1
  private_key_pem = tls_private_key.issuer[0].private_key_pem

  subject {
    common_name = "identity.linkerd.cluster.local"
  }
}

resource "tls_locally_signed_cert" "issuer" {
  count              = var.external_ca ? 0 : 1
  cert_request_pem   = tls_cert_request.issuer[0].cert_request_pem
  ca_private_key_pem = tls_private_key.trust_anchor[0].private_key_pem
  ca_cert_pem        = tls_self_signed_cert.trust_anchor[0].cert_pem

  validity_period_hours = 8760
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

resource "helm_release" "linkerd_control_plane" {
  name       = "linkerd-control-plane"
  repository = "https://helm.linkerd.io/edge"
  chart      = "linkerd-control-plane"
  namespace  = "linkerd"
  timeout    = 600

  dynamic "set" {
    for_each = var.external_ca ? [1] : []
    content {
      name  = "identity.externalCA"
      value = true
    }
  }

  dynamic "set" {
    for_each = var.external_ca ? [1] : []
    content {
      name  = "identity.issuer.scheme"
      value = "kubernetes.io/tls"
    }
  }

  dynamic "set" {
    for_each = var.external_ca ? [] : [1]
    content {
      name  = "identityTrustAnchorsPEM"
      value = tls_self_signed_cert.trust_anchor[0].cert_pem
    }
  }

  dynamic "set" {
    for_each = var.external_ca ? [] : [1]
    content {
      name  = "identity.issuer.tls.crtPEM"
      value = tls_locally_signed_cert.issuer[0].cert_pem
    }
  }

  dynamic "set" {
    for_each = var.external_ca ? [] : [1]
    content {
      name  = "identity.issuer.tls.keyPEM"
      value = tls_private_key.issuer[0].private_key_pem
    }
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
  timeout          = 600

  depends_on = [helm_release.linkerd_control_plane]
}
