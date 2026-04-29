# Terragrunt Infrastructure — payments-app

AWS infra for payments-app. Runs on MiniStack (local) or real AWS. Terragrunt orchestrates Terraform units.

## Repo Layout

```
root.hcl              — root config: provider/backend generation, versions
common.hcl            — shared locals: project="terragrunt-infra", region="ap-southeast-1"
envs/
  production.hcl      — production feature flags (real AWS, all features on)
  ministack.hcl       — ministack feature flags (use_ministack=true, nat disabled, github-runner disabled)
_common/
  vault_provider.hcl  — shared Vault token fetch (SSM) + port-forward hook + vault/k8s providers
  k8s_providers.hcl   — shared EKS dependency + helm/kubernetes providers
stacks/vault-consul/
  production/
    env.hcl                — locals { name = "production" }
    terragrunt.stack.hcl   — stack definition (7 layers, all units)
  ministack/
    env.hcl                — locals { name = "ministack" }
    terragrunt.stack.hcl   — stack definition (6 layers, no github-runner)
units/<name>/         — individual Terraform modules (main.tf, variables.tf, outputs.tf, terragrunt.hcl)
gitops/
  appset.yaml         — ArgoCD ApplicationSet (4 waves)
  values/             — Helm values per app
```

## Units

| Unit | Layer | Purpose |
|------|-------|---------|
| vpc | 1 | VPC, subnets, NAT |
| eks | 2 | EKS / k3s cluster |
| kms | 3 | KMS key for Vault auto-unseal |
| rds | 4 | PostgreSQL RDS |
| vault | 4 | Vault on k8s (Helm) |
| certs | 5 | TLS certs (tls provider) |
| vault-config | 5 | Vault secrets engines, PKI, DB dynamic creds |
| linkerd | 6 | Service mesh |
| argocd | 6 | GitOps controller |
| github-runner | 7 | ARC self-hosted runner (AWS only) |

## GitOps Waves (ArgoCD)

Wave 1: consul → Wave 2: aws-alb + datadog → Wave 3: flagger → Wave 4: payments-app

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
make gitops-bootstrap                  # kubectl apply gitops/appset.yaml

# Utility
make tg-clean                          # rm .terragrunt-cache / .terraform dirs
make fmt                               # terraform fmt -recursive units/
source load_env.sh production          # Export KUBECONFIG, VAULT_ADDR, etc.
source load_env.sh ministack           # Same for local dev
```

## Environment Detection

No toggle file. Env is determined by **which stack directory you run from**:
- `stacks/vault-consul/production/` → reads `production/env.hcl` → loads `envs/production.hcl`
- `stacks/vault-consul/ministack/`  → reads `ministack/env.hcl`  → loads `envs/ministack.hcl`

`root.hcl` uses `find_in_parent_folders("env.hcl")` to resolve the env automatically.

- **production**: real AWS credentials, all features on
- **ministack**: endpoint=http://localhost:4566, creds=test/test, no NAT, no github-runner

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

- aws ~> 5.0, helm ~> 2.0, kubernetes ~> 2.0, vault ~> 4.0, tls ~> 4.0
- terraform >= 1.7, terragrunt >= 1.0.2
