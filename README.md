# Terragrunt Infrastructure Stack

AWS infrastructure for **payments-app** — Vault, Linkerd, ArgoCD GitOps via Terragrunt.
Runs on [MiniStack](https://github.com/ministackorg/ministack) (local) or real AWS.

## Quick Start

```bash
# Local
make ms-bootstrap          # Deploy everything from scratch (~4 min)
source load_env.sh         # Export KUBECONFIG, VAULT_ADDR, etc.

# AWS
make ms-disable            # Switch to AWS
make stack-vault apply     # Deploy infrastructure
make gitops-bootstrap      # Bootstrap ArgoCD (once)
source load_env.sh
```

## Stack Layers

| Layer | Units | Purpose |
| ----- | ----- | ------- |
| 1 | vpc | Network |
| 2 | eks | Compute (k3s / EKS) |
| 3 | kms | Vault auto-unseal |
| 4 | vault, rds | Secrets + Database |
| 5 | certs, vault-config | PKI + Vault config |
| 6 | linkerd, argocd | Service mesh + GitOps |
| 7 | github-runner | CI/CD (AWS only) |

ArgoCD then deploys: consul → aws-alb + datadog → flagger → payments-app

## Commands

```bash
make ms-bootstrap          # Full local bootstrap
make stack-vault apply     # Apply all units
make vault-status          # Vault health
make vault-db-creds        # Dynamic DB credentials
make gitops-bootstrap      # ArgoCD ApplicationSet
make ms-teardown           # Stop local env
make tg-clean              # Clear cache
```

## Docs

- [Architecture diagrams](docs/architecture.md) — network topology, vault flow, env comparison

## Prerequisites

Terragrunt ≥ 0.77 · Terraform ≥ 1.13 · Docker (OrbStack recommended) · kubectl · Helm 3 · AWS CLI v2
