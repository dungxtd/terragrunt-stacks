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

unit "rds" {
  source = "../../units/rds"
  path   = "rds"
}

unit "linkerd" {
  source = "../../units/linkerd"
  path   = "linkerd"
}

unit "argocd" {
  source = "../../units/argocd"
  path   = "argocd"

  values = {
    enable_consul_project = false
  }
}

unit "aws_alb" {
  source = "../../units/aws-alb"
  path   = "aws-alb"
}

unit "sops_secrets" {
  source = "../../units/sops-secrets"
  path   = "sops-secrets"
}

unit "datadog" {
  source = "../../units/datadog"
  path   = "datadog"
}

# ── Layer 5: Progressive Delivery ────────────────────────────────

unit "flagger" {
  source = "../../units/flagger"
  path   = "flagger"

  values = {
    mesh_provider  = "linkerd"
    metrics_server = "http://prometheus.linkerd-viz:9090"
  }
}
