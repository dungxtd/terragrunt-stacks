# Terragrunt Infrastructure Stack

AWS infrastructure for **payments-app** — Vault, Linkerd, ArgoCD GitOps via Terragrunt.
Runs on [MiniStack](https://github.com/ministackorg/ministack) (local) or real AWS.

## Quick Start

```bash
# Local
make ms-bootstrap          # Deploy everything from scratch (~4 min)
source scripts/load_env.sh         # Export KUBECONFIG, VAULT_ADDR, etc.

# AWS
make ms-disable            # Switch to AWS
make stack-vault apply     # Deploy infrastructure
make gitops-bootstrap      # Bootstrap ArgoCD (once)
source scripts/load_env.sh
```

## Stack Layers

| Layer | Units | Purpose |
| ----- | ----- | ------- |
| 1 | vpc | Network |
| 2 | eks | Compute (k3s / EKS) |
| 3 | kms | Vault auto-unseal |
| 4 | vault-irsa (AWS HA only), vault, rds | Secrets + Database |
| 5 | certs, vault-config | PKI + Vault config |
| 6 | aws-alb, linkerd, argocd, alb | LB controller + service mesh + GitOps + TF-managed ALB |
| 7 | github-runner | CI/CD (AWS only) |

ArgoCD then deploys (sync waves): external-secrets → secret-stores → kube-prometheus-stack → flagger/loadtester → payments-app → jaeger-demo

## Commands

```bash
make ms-bootstrap          # Full local bootstrap
make stack-vault apply     # Apply all units
make vault-status          # Vault health
make vault-db-creds        # Dynamic DB credentials
make gitops-bootstrap      # ArgoCD ApplicationSet
make pf-all                # Port-forward all UIs (ArgoCD/Vault/Linkerd/Jaeger/HotROD/Grafana/Prometheus/payments-app)
make pf-stop               # Stop all port-forwards
make ms-teardown           # Stop local env
make tg-clean              # Clear cache
```

## UIs (after `make pf-all`)

| URL | Service | Login |
|-----|---------|-------|
| http://localhost:8080 | ArgoCD | admin / `make argocd-password` |
| http://localhost:8200 | Vault | token from SSM (`make vault-status`) |
| http://localhost:8084 | Linkerd-viz | none |
| http://localhost:16686 | Jaeger | none |
| http://localhost:8090 | HotROD demo | none |
| http://localhost:3000 | Grafana | admin / admin |
| http://localhost:9090 | Prometheus | none |
| http://localhost:8082 | payments-app | (Spring Boot REST) |

## AWS Authentication

| Context | Method | Details |
|---|---|---|
| **Local dev** | `AWS_PROFILE` / `aws configure` | Set via `source scripts/load_env.sh` or `export AWS_PROFILE=...` |
| **CI/CD** | OIDC federation | GitHub Actions assumes `AWS_ROLE_ARN` via `aws-actions/configure-aws-credentials` |

> **Do not** add `--profile` flags to the Makefile — it breaks CI where OIDC env vars are injected automatically.

## Repo Layout

```
terraform/         (units/<name>)        — TF modules, one per resource group
stacks/            vault-consul/{prod,ms}/ — terragrunt stack definitions per env
gitops/            apps/, charts/, values/, platform/     — ArgoCD-managed runtime
ministack/         docker-compose.yml + entrypoint.sh     — local dev stack
scripts/           load_env.sh                              — shell helpers
makefiles/         stacks.mk units.mk helm.mk vault.mk ... — modular Makefile parts
docs/              architecture.md, adr/, runbooks/, archive/
```

## Docs

- **[Platform Guide](docs/PLATFORM_GUIDE.md)** — components, end-to-end flows, all use cases (start here)
- **[Cluster Lifecycle Runbook](docs/runbooks/cluster-lifecycle.md)** — step-by-step apply/destroy + request flow + Vault deep dive
- [Architecture](docs/architecture.md) — network topology, vault flow, env comparison
- [ADRs](docs/adr/) — decisions: mesh choice, Vault production mode, ALB grouping, Vault init Tier 1
- [Runbooks](docs/runbooks/) — fix recipes: canary stuck, vault HA migration, cluster lifecycle
- [GitOps](gitops/README.md) — App-of-Apps layout, sync waves, payments-app chart

## Prerequisites

Terragrunt ≥ 1.0.3 · Terraform ≥ 1.12 · Docker (OrbStack recommended) · kubectl · Helm 3 · AWS CLI v2
