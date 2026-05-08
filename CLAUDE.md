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
  apps/               — ArgoCD App-of-Apps: root.yaml, appset-platform.yaml, payments-app.yaml
  charts/             — in-house Helm charts (_lib library + payments-app)
  values/<app>/<env>.yaml — per-app per-env Helm values
  platform/linkerd-viz-policy/ — raw k8s manifests (Linkerd-Viz authz policy)
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
| vault | 4 | Vault on k8s (Helm) + Vault Secrets Operator |
| vault-config | 5 | Vault secrets engines, PKI, DB dynamic creds |
| linkerd | 6 | Service mesh |
| argocd | 6 | GitOps controller |
| aws-alb | 6 | AWS ALB Ingress controller (IRSA + Helm) |
| alb | 6 | TF-managed ALB + TargetGroup + TargetGroupBinding (frontend) |
| github-runner | 7 | ARC self-hosted runner (AWS only) |


## GitOps Waves (ArgoCD — App-of-Apps in gitops/apps/, NOT Terraform)

Wave 0: external-secrets → Wave 1: secret-stores → Wave 2: kube-prometheus-stack → Wave 3: argo-rollouts (flagger/loadtester commented out) → Wave 4: payments-app

Pinned chart versions live in `gitops/apps/appset-platform.yaml`:
kube-prometheus-stack=65.2.0, flagger=1.43.0 (commented), loadtester=0.37.0 (commented), argo-rollouts=2.40.9 (controller v1.9.0)

Argo Rollouts uses real HTTP traffic split via Gateway API plugin (`argoproj-labs/gatewayAPI` v0.13.0): plugin patches `HTTPRoute.spec.rules[*].backendRefs[*].weight` between stable+canary Services. Linkerd 2.14+ HTTPRoute parentRef=Service. Canary safety: smoke-test (Job/curl) + Linkerd success-rate + p99 latency AnalysisTemplates from Linkerd-viz Prometheus (`direction=outbound`, queried from caller side to bypass `skip-inbound-ports` on payments-app). Per-service knobs in values: `rollout: true`, `gatewayHttpRoute: true`, `replicas: 2`. PDB rendered automatically by `lib.rollout` (`minAvailable: 1`).

Flagger is disabled in code: AppSet entries for flagger + loadtester are commented out in `gitops/apps/appset-platform.yaml`; argo-rollouts is the active progressive-delivery controller. Flagger values files (`gitops/values/flagger/production.yaml`, `gitops/values/loadtester/production.yaml`) and `_canary.tpl` template kept intact. Canary CR rendering is gated by `canary.enabled` + per-service `canary` flag in `gitops/values/payments-app/production.yaml` (both currently false). Re-enable flagger: uncomment AppSet entries + flip canary flags.

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
- `rds_master_secret_arn` = `""` in ministack — set `rds_master_password` directly in ministack `env.hcl` instead

## Provider Versions

- aws ~> 6.42, helm ~> 3.1, kubernetes ~> 2.35, vault ~> 5.2, tls ~> 4.0
- terraform >= 1.12, terragrunt >= 1.0.3

## vault-config Notes

- `rds_master_secret_arn` — required in production (sourced from `rds` unit output). Leave `""` for ministack.
- `rds_master_password` — ministack/dev only direct password fallback. Both empty = hard fail at `terraform apply`.
- DB engine path: `payments-app/database`, role: `payments`, TTL: 1h/24h max.
- Vault Agent Injector annotations set `agent-init-first: "true"` (init completes before app starts) and `agent-pre-populate-only: "false"` (sidecar renews creds). Defined in `gitops/charts/_lib/templates/_vault.tpl`.
