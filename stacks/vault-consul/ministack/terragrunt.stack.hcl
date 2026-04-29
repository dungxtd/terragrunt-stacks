# ── Layer 1: Network ─────────────────────────────────────────────

unit "vpc" {
  source = "../../../units/vpc"
  path   = "vpc"
}

# ── Layer 2: Compute ─────────────────────────────────────────────

unit "eks" {
  source = "../../../units/eks"
  path   = "eks"
}

# ── Layer 3: Security ────────────────────────────────────────────

unit "kms" {
  source = "../../../units/kms"
  path   = "kms"
}

# ── Layer 4: Data + Vault ────────────────────────────────────────

unit "rds" {
  source = "../../../units/rds"
  path   = "rds"
}

unit "vault" {
  source = "../../../units/vault"
  path   = "vault"
}

# ── Layer 5: Vault Config + PKI ──────────────────────────────────

unit "certs" {
  source = "../../../units/certs"
  path   = "certs"
}

unit "vault_config" {
  source = "../../../units/vault-config"
  path   = "vault-config"
}

# ── Layer 6: Platform + GitOps ───────────────────────────────────

unit "linkerd" {
  source = "../../../units/linkerd"
  path   = "linkerd"
}

unit "argocd" {
  source = "../../../units/argocd"
  path   = "argocd"
}

# github-runner disabled for ministack (no ARC support locally)
