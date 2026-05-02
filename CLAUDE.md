# Terragrunt Infrastructure — payments-app

AWS infra for payments-app. Runs on MiniStack (local) or real AWS. Terragrunt orchestrates Terraform units.

## Repo Layout

```
root.hcl              — root config: versions generate, delegates provider/backend to env.hcl
common.hcl            — shared locals: project="terragrunt-infra", region="ap-southeast-1"
_common/
  vault_provider.hcl  — shared vault dependency + root token provider + port-forward hook
  k8s_providers.hcl   — shared EKS dependency + helm/kubernetes providers
stacks/vault-consul/
  production/
    env.hcl                — full per-env config (provider, backend, feature flags, kubeconfig, vault, RDS overrides)
    terragrunt.stack.hcl   — stack definition (7 layers, all units)
  ministack/
    env.hcl                — full per-env config (provider, backend, NAT disabled, etc.)
    terragrunt.stack.hcl   — stack definition (6 layers, no github-runner)
units/<name>/         — individual Terraform modules (main.tf, variables.tf, outputs.tf, terragrunt.hcl)
gitops/
  apps/               — ArgoCD App-of-Apps: root.yaml, appset-platform.yaml, payments-app.yaml, platform-ui.yaml
  charts/             — in-house Helm charts (_lib library + payments-app)
  values/<app>/<env>.yaml — per-app per-env Helm values
  platform/platform-ui/ — raw ALB Ingress manifests
ministack/            — local dev: docker-compose.yml + entrypoint.sh
scripts/              — load_env.sh
makefiles/            — modular Makefile parts (stacks, units, helm, k8s, vault, ministack, util)
docs/                 — architecture.md, adr/, runbooks/, archive/
```

## Units (Terraform)

| Unit | Layer | Purpose |
|------|-------|---------|
| vpc | 1 | VPC, subnets, NAT |
| eks | 2 | EKS / k3s cluster |
| kms | 3 | KMS key for Vault auto-unseal |
| rds | 4 | PostgreSQL RDS |
| vault-irsa | 4 | AWS HA only: IAM role for Vault KMS auto-unseal |
| vault | 4 | Vault on k8s (Helm) |
| certs | 5 | TLS certs (tls provider) |
| vault-config | 5 | Vault secrets engines, PKI, DB dynamic creds |
| linkerd | 6 | Service mesh |
| argocd | 6 | GitOps controller |
| aws-alb | 6 | AWS ALB Ingress controller (IRSA) |
| github-runner | 7 | ARC self-hosted runner (AWS only) |

## GitOps Waves (ArgoCD — App-of-Apps in gitops/apps/, NOT Terraform)

Wave 1: consul → Wave 2: datadog → Wave 3: flagger → Wave 4: payments-app → Wave 5: platform-ui

Pinned chart versions live in `gitops/apps/appset-platform.yaml`:
consul=1.9.7, datadog=3.205.0, flagger=1.43.0

## Key Commands

```bash
# Local dev (MiniStack)
make ms-bootstrap                      # Full bootstrap from scratch (~4 min)
make ms-up / ms-down                   # Docker compose up/down
make ms-reset                          # Clear MiniStack state via API
make ms-seed                           # Create S3 bucket + DynamoDB lock table
make ms-kubeconfig                     # Write .kubeconfig-ministack from k3s container

# Stack — env determined by target name, no flag needed
make stack-vault-production apply|plan|destroy
make stack-vault-ministack  apply|plan|destroy

# Units
make apply-<unit> / plan-<unit> / destroy-<unit>

# Vault
make vault-status / vault-db-creds / vault-pki-roots / vault-rotate-db

# GitOps
make gitops-bootstrap                  # kubectl apply gitops/apps/root.yaml (App-of-Apps)
make alb-crds                          # apply aws-load-balancer-controller CRDs (after v3.x bump)

# Utility
make help                              # list all targets (auto-generated from ## comments)
make tg-clean                          # rm .terragrunt-cache / .terraform dirs
make fmt                               # terraform fmt -recursive units/
source scripts/load_env.sh production  # Export KUBECONFIG, VAULT_ADDR, etc.
source scripts/load_env.sh ministack   # Same for local dev
```

## Environment Detection

No toggle file. Env is determined by **which stack directory you run from**:
- `stacks/vault-consul/production/env.hcl` carries the full production config
- `stacks/vault-consul/ministack/env.hcl`  carries the full ministack config

`root.hcl` uses `find_in_parent_folders("env.hcl")` to resolve the env automatically. Each env.hcl is self-contained: it carries its own `provider_content` (AWS provider block) and `backend_config` (S3 backend map). root.hcl just passes them through — no flags, no ternaries.

- **production**: real AWS credentials, all features on
- **ministack**: LocalStack endpoint, test creds, no NAT, no github-runner

## _common Includes

Units include `_common/vault_provider.hcl` or `_common/k8s_providers.hcl` via `read_terragrunt_config`. These files:
- Declare the shared `dependency` block (vault or eks)
- Generate provider TF files
- `vault_provider.hcl` also adds a `before_hook` to auto port-forward Vault on apply/plan/destroy

## MiniStack Details

- LocalStack-compatible AWS emulator at port 4566
- EKS = k3s in Docker (container: `ministack-eks-terragrunt-infra-eks`)
- RDS = real Postgres at port 15432
- State: S3 bucket `tf-state-terragrunt-infra-ap-southeast-1`, DynamoDB table `tf-state-lock`
- Kubeconfig: `.kubeconfig-ministack` in repo root

## Provider Versions

- aws ~> 6.42, helm ~> 3.1, kubernetes ~> 2.35, vault ~> 5.2, tls ~> 4.0
- terraform >= 1.12, terragrunt >= 1.0.3
