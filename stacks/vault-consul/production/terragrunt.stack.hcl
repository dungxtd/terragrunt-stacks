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

unit "vault_irsa" {
  source = "../../../units/vault-irsa"
  path   = "vault-irsa"
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

unit "aws_alb" {
  source = "../../../units/aws-alb"
  path   = "aws-alb"
}

# linkerd and argocd depend on aws_alb: ALB controller registers a MutatingWebhook
# (mservice.elbv2.k8s.aws). If the ALB pod isn't ready when Linkerd creates Services,
# the webhook call fails. Explicit dependency ensures ALB is up first.
unit "linkerd" {
  source     = "../../../units/linkerd"
  path       = "linkerd"
  depends_on = [unit.aws_alb]
}

unit "argocd" {
  source     = "../../../units/argocd"
  path       = "argocd"
  depends_on = [unit.aws_alb]
}

# ── Layer 7: CI/CD Runner ────────────────────────────────────────

unit "github_runner" {
  source = "../../../units/github-runner"
  path   = "github-runner"
}
