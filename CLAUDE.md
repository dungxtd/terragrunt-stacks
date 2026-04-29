# Terragrunt Infrastructure — payments-app

AWS infra for payments-app. Runs on MiniStack (local) or real AWS. Terragrunt orchestrates Terraform units.

## Repo Layout

```
root.hcl              — root config: provider/backend generation, versions
common.hcl            — shared locals: project="terragrunt-infra", region="ap-southeast-1"
local.hcl             — active_env: "ministack" | "aws"  ← switch with make ms-enable/ms-disable
envs/ministack.hcl    — ministack feature flags (use_ministack=true, nat disabled, github-runner disabled)
envs/aws.hcl          — aws feature flags (all enabled)
_common/
  vault_provider.hcl  — shared Vault dependency + port-forward hook + vault/k8s providers
  k8s_providers.hcl   — shared EKS dependency + helm/kubernetes providers
stacks/vault-consul/
  terragrunt.stack.hcl — stack definition (7 layers, all units)
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
# Local dev
make ms-bootstrap          # Full bootstrap from scratch (~4 min)
make ms-enable / ms-disable # Switch active_env in local.hcl
make ms-up / ms-down        # Docker compose up/down
make ms-reset               # Clear MiniStack state via API
make ms-seed                # Create S3 bucket + DynamoDB lock table
make ms-kubeconfig          # Write .kubeconfig-ministack from k3s container

# Stack
make stack-vault apply|plan|destroy

# Units
make apply-<unit> / plan-<unit> / destroy-<unit>

# Vault
make vault-status / vault-db-creds / vault-pki-roots / vault-rotate-db

# GitOps
make gitops-bootstrap       # kubectl apply gitops/appset.yaml

# Utility
make tg-clean               # rm .terragrunt-cache / .terraform dirs
make fmt                    # terraform fmt -recursive units/
source load_env.sh          # Export KUBECONFIG, VAULT_ADDR, etc.
```

## Environment Toggle

`local.hcl` holds `active_env`. `root.hcl` reads it → selects provider, backend, and feature flags.

- **ministack**: endpoint=http://localhost:4566, creds=test/test, no NAT, no github-runner
- **aws**: real AWS credentials from CLI/instance profile, all features on

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
- terraform >= 1.7, terragrunt >= 0.77
