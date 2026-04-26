# ── Layer 1: Network ─────────────────────────────────────────────

unit "vpc" {
  source = "../../units/vpc"
  path   = "vpc"
}

# ── Layer 2: Compute ─────────────────────────────────────────────

unit "eks" {
  source = "../../units/eks"
  path   = "eks"
}

# ── Layer 3: Security ────────────────────────────────────────────

unit "kms" {
  source = "../../units/kms"
  path   = "kms"
}

# ── Layer 4: Platform (parallel) ─────────────────────────────────

unit "vault" {
  source = "../../units/vault"
  path   = "vault"
}

unit "consul" {
  source = "../../units/consul"
  path   = "consul"
}

unit "argocd" {
  source = "../../units/argocd"
  path   = "argocd"

  values = {
    enable_consul_project = true
  }
}

unit "rds" {
  source = "../../units/rds"
  path   = "rds"
}

unit "datadog" {
  source = "../../units/datadog"
  path   = "datadog"
}

# ── Layer 5: PKI + Vault Config ──────────────────────────────────

unit "certs" {
  source = "../../units/certs"
  path   = "certs"
}

unit "vault_config" {
  source = "../../units/vault-config"
  path   = "vault-config"
}

# ── Layer 6: Progressive Delivery ────────────────────────────────

unit "flagger" {
  source = "../../units/flagger"
  path   = "flagger"

  values = {
    mesh_provider  = "consul"
    metrics_server = "http://prometheus-server.default:9090"
  }
}
