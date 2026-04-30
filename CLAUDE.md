# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Terragrunt Infrastructure — payments-app

AWS infra for payments-app. Runs on MiniStack (local) or real AWS. Terragrunt orchestrates Terraform units into layered stacks.

## Prerequisites

Terragrunt ≥ 1.0.3 · Terraform ≥ 1.12 · Docker (OrbStack recommended) · kubectl · Helm 3 · AWS CLI v2

## Key Commands

```bash
# Local dev (MiniStack)
make ms-bootstrap                      # Full bootstrap: tg-clean → ms-reset → ms-seed → stack apply → gitops-bootstrap
make ms-up / ms-down                   # Docker compose up/down
make ms-reset                          # Wipe all MiniStack state via API
make ms-seed                           # Create S3 bucket + DynamoDB lock table (also calls ms-up)
make ms-kubeconfig                     # Write .kubeconfig-ministack from k3s container

# Stack operations — env detected from directory path, no flag needed
make stack-vault-production apply|plan|destroy
make stack-vault-ministack  apply|plan|destroy
make stack-vault-production-generate   # Generate stack without running it

# Single units
make apply-<unit> / plan-<unit> / destroy-<unit>
# Units: vpc eks kms rds vault vault-config certs consul argocd linkerd flagger datadog aws-alb github-runner

# Vault operations
make vault-status                      # Health check via port-forward
make vault-db-creds                    # Generate dynamic DB credentials
make vault-pki-roots                   # Fetch Consul PKI CA chain
make vault-rotate-db                   # Rotate DB root credentials
make vault-lease-clean                 # Revoke all leases for payments-app

# Kubernetes / GitOps
make kubeconfig                        # Update ~/.kube/config from EKS (production)
make gitops-bootstrap                  # kubectl apply gitops/appset.yaml
make argocd-password                   # Print ArgoCD initial admin password

# Testing
make ms-test                           # Test MiniStack connectivity (STS, S3, EC2)
make test-app                          # curl payments-app service
make test-db                           # pg_isready against RDS
make test-mesh                         # Verify Linkerd/Envoy sidecar

# Utility
make tg-clean                          # rm .terragrunt-cache / .terragrunt-stack / .terraform dirs
make fmt                               # terraform fmt -recursive units/ && terragrunt hcl fmt
make graph-vault                       # Print Terragrunt dependency graph for vault-consul stack

# Environment export
source load_env.sh production          # Export KUBECONFIG, VAULT_ADDR, VAULT_TOKEN, ARGOCD_SERVER, etc.
source load_env.sh ministack           # Same for local dev (defaults to production if no arg)
```

## Architecture

### Config Resolution Chain

Environment is determined by **which stack directory you run from** — there is no toggle file:

```
stacks/vault-consul/<env>/             ← entry point
  env.hcl                              ← locals { name = "production"|"ministack" }
    → root.hcl reads find_in_parent_folders("env.hcl")
      → loads envs/<name>.hcl          ← all feature flags and env-specific values
        → common.hcl                   ← project="terragrunt-infra", region="ap-southeast-1"
```

`root.hcl` generates `provider.tf`, `backend.tf`, and `versions.tf` into every unit at runtime. The provider block switches between real AWS and MiniStack endpoint based on `use_ministack`.

### Stack Layers

Both production and ministack stacks define the same 10 units. The github-runner unit is disabled in ministack via `enable_github_runner=false` feature flag (not by omitting it from the stack definition).

| Layer | Unit(s) | Purpose |
|-------|---------|---------|
| 1 | vpc | VPC, subnets, NAT (NAT disabled in ministack) |
| 2 | eks | EKS / k3s cluster |
| 3 | kms | KMS key for Vault auto-unseal |
| 4 | vault, rds | Vault on k8s (Helm) + PostgreSQL |
| 5 | certs, vault-config | Vault PKI backends + secrets engines |
| 6 | linkerd, argocd | Service mesh + GitOps controller |
| 7 | github-runner | ARC self-hosted runner (AWS only) |

ArgoCD then deploys via GitOps waves: **Wave 1** consul → **Wave 2** aws-alb + datadog → **Wave 3** flagger → **Wave 4** payments-app

### `_common` Includes

Units include shared configs via `read_terragrunt_config`. A unit that includes one of these must NOT declare its own matching `dependency` or `provider` block.

- **`_common/k8s_providers.hcl`** — declares `dependency "eks"`, generates `helm` and `kubernetes` providers using `kubeconfig_path` from env config (uses kubeconfig file, not live EKS cluster outputs). Used by: vault, argocd, linkerd, flagger, consul.
- **`_common/vault_provider.hcl`** — declares `dependency "vault"`, generates `vault` provider (fetches token from SSM at parse time), generates `helm`+`kubernetes` providers, and adds a `before_hook` that auto-port-forwards Vault to `:18200` on every apply/plan/destroy. Used by: vault-config, certs.

Vault token retrieval is env-specific: ministack uses `aws ssm get-parameter --endpoint-url http://localhost:4566 ... || echo root`; production fetches from real SSM Parameter Store (`/terragrunt-infra/vault/root-token`).

### vault-config Unit — Required Environment Variables

The `vault-config` unit requires these env vars before apply (not managed by Terragrunt):

```bash
export RDS_MASTER_PASSWORD=...            # RDS master password
export PAYMENTS_PROCESSOR_PASSWORD=...    # Static KV credential for payments-processor
```

In ministack these default to `"password"` via `rds_password_override` in `envs/ministack.hcl`.

### Vault Secrets Engines (configured by vault-config unit)

- **Transit** (`transit/`): encryption key `payments-app` (aes256-gcm96) for payment data
- **Database** (`payments-app/database/`): dynamic PostgreSQL creds, TTL 1h/24h max; MiniStack connects to `host.docker.internal:15432`, production to RDS endpoint
- **KV v2** (`payments-processor/static/`): static credentials for payments-processor
- **PKI** (3 backends): `consul/server/pki`, `consul/connect/pki`, `consul/api-gw/pki` for Consul TLS

### MiniStack Details

- LocalStack-compatible AWS emulator at `localhost:4566` (credentials: `test`/`test`)
- EKS = k3s in Docker with host networking (container: `ministack-eks-terragrunt-infra-eks`)
- RDS = real Postgres 15 at `localhost:15432` (accessed inside k8s via `host.docker.internal:15432`)
- Vault = dev mode, root token = `root`, no HA
- State: S3 bucket `tf-state-terragrunt-infra-ap-southeast-1`, DynamoDB table `tf-state-lock`
- Kubeconfig: `.kubeconfig-ministack` in repo root
- ArgoCD: NodePort at `localhost:30443`

Production state bucket: `tf-state-terragrunt-stacks` (real S3, key per unit path).

### Provider Versions

Generated by `root.hcl` into `versions.tf` for every unit:

- `aws ~> 6.42`, `helm ~> 3.1`, `kubernetes ~> 2.35`, `vault ~> 5.2`, `tls ~> 4.0`
- Terraform `>= 1.12`, Terragrunt `>= 1.0.3`

## CI/CD Pipeline

`.github/workflows/deploy.yml` runs on push/PR to `main`:

1. **Validate** — HCL format check (`make fmt` + `git diff --exit-code`), AWS OIDC auth, stack generate, `terragrunt run --all validate`, Checkov policy scan (skips: `CKV_AWS_144,CKV_AWS_18,CKV_TF_1,CKV2_AWS_5`)
2. **Plan** — IAM policy simulation, `make stack-vault-production plan`, posts plan diff as PR comment
3. **Apply** — Runs `make stack-vault-production apply` only on push to `main` (requires `production` environment approval)

AWS auth is OIDC via `secrets.AWS_ROLE_ARN` — do not add `--profile` flags to the Makefile as it breaks CI. GitHub runner secrets required: `AWS_ROLE_ARN`, `GITHUB_CONFIG_URL`, `ARC_APP_ID`, `ARC_APP_INSTALLATION_ID`, `ARC_APP_PRIVATE_KEY`.
