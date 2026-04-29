# Vault + ArgoCD GitOps Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SOPS-based secret management with Vault + ArgoCD ApplicationSet GitOps — Terraform bootstraps infra+Vault, ArgoCD owns all k8s workloads.

**Architecture:** Terraform deploys vpc/eks/kms/rds/vault (auto-init via null_resource)/vault-config/argocd. ArgoCD ApplicationSet then deploys consul (wave 1), aws-alb+datadog (wave 2), flagger (wave 3), payments-app (wave 4). Vault Secrets Operator (already in vault unit) syncs Vault secrets to k8s Secrets consumed by apps.

**Tech Stack:** Terragrunt, Terraform, HashiCorp Vault, ArgoCD ApplicationSets, Vault Secrets Operator, AWS SSM (SecureString), LocalStack/MiniStack.

---

## File Map

**Delete:**
- `units/sops-secrets/` (entire directory)
- `stacks/sops-linkerd/` (entire directory)
- `helm/payments-app/values/sops-linkerd.yaml`

**Rename:**
- `helm/` → `gitops/charts/`

**Modify:**
- `units/eks/terragrunt.hcl` — add after_hook to auto-generate kubeconfig post-apply
- `units/vault/main.tf` — add auto-init null_resource + SSM data source
- `units/vault/outputs.tf` — expose vault_root_token from SSM
- `units/vault/variables.tf` — add ssm_endpoint, kubeconfig_path, use_ministack
- `units/vault/terragrunt.hcl` — pass new variables from env_cfg
- `units/certs/variables.tf` — add vault_token
- `units/certs/main.tf` — use vault_token in provider
- `units/certs/terragrunt.hcl` — read vault_root_token from vault dependency
- `units/vault-config/variables.tf` — add vault_token
- `units/vault-config/main.tf` — use vault_token in provider, add rotate-root null_resource
- `units/vault-config/terragrunt.hcl` — read vault_root_token from vault dependency
- `stacks/vault-consul/terragrunt.stack.hcl` — remove consul, datadog, flagger
- `Makefile` — remove sops targets, add gitops-bootstrap + vault-rotate-db

**Create:**
- `gitops/appset.yaml` — ArgoCD ApplicationSet (consul → aws-alb/datadog → flagger → payments-app)
- `gitops/values/consul.yaml` — Consul Helm values for ArgoCD
- `gitops/values/datadog.yaml` — Datadog Helm values for ArgoCD
- `gitops/values/flagger.yaml` — Flagger Helm values for ArgoCD

---

## Task 1: Delete SOPS artifacts

**Files:**
- Delete: `units/sops-secrets/`
- Delete: `stacks/sops-linkerd/`
- Delete: `helm/payments-app/values/sops-linkerd.yaml`

- [ ] **Step 1: Delete sops units and stack**

```bash
rm -rf units/sops-secrets
rm -rf stacks/sops-linkerd
rm -f helm/payments-app/values/sops-linkerd.yaml
```

- [ ] **Step 2: Verify deletions**

```bash
ls units/ | grep sops          # should return nothing
ls stacks/ | grep sops         # should return nothing
ls helm/payments-app/values/   # should only show vault-consul.yaml
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove sops-linkerd stack and sops-secrets unit"
```

---

## Task 2: Rename helm/ → gitops/charts/

**Files:**
- Rename: `helm/` → `gitops/charts/`
- Modify: `gitops/charts/payments-app/Chart.yaml`

- [ ] **Step 1: Move directory**

```bash
mkdir -p gitops
git mv helm gitops/charts
```

- [ ] **Step 2: Update Chart.yaml description**

Edit `gitops/charts/payments-app/Chart.yaml`:
```yaml
apiVersion: v2
name: payments-app
description: Payments application — vault-consul GitOps deployment
type: application
version: 1.0.0
appVersion: "1.0.0"
```

- [ ] **Step 3: Verify chart structure**

```bash
ls gitops/charts/payments-app/
# Chart.yaml  templates/  values/
ls gitops/charts/payments-app/values/
# vault-consul.yaml
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: rename helm/ to gitops/charts/"
```

---

## Task 3: EKS unit — auto-generate kubeconfig after apply

**Files:**
- Modify: `units/eks/terragrunt.hcl`

Both hooks run on every apply; the wrong one silently fails (`run_on_error = false`, `|| true`), so this is safe for both ministack and real AWS.

- [ ] **Step 1: Add after_hooks to units/eks/terragrunt.hcl**

```hcl
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  common  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  env_cfg = include.root.locals.env_cfg
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id          = "vpc-mock"
    private_subnets = ["subnet-a", "subnet-b", "subnet-c"]
  }
}

inputs = {
  project         = local.common.locals.project
  vpc_id          = dependency.vpc.outputs.vpc_id
  private_subnets = dependency.vpc.outputs.private_subnets
  tags            = local.common.locals.common_tags

  create_cluster_security_group            = local.env_cfg.locals.create_cluster_security_group
  create_node_security_group               = local.env_cfg.locals.create_node_security_group
  create_cluster_addons                    = local.env_cfg.locals.create_cluster_addons
  enable_cluster_creator_admin_permissions = local.env_cfg.locals.enable_cluster_creator_admin_permissions
  update_launch_template_default_version   = local.env_cfg.locals.update_launch_template_default_version
}

terraform {
  after_hook "gen_kubeconfig_ministack" {
    commands     = ["apply"]
    execute      = ["bash", "-c",
      "docker exec ministack-eks-terragrunt-infra-eks cat /etc/rancher/k3s/k3s.yaml 2>/dev/null | sed 's|127.0.0.1|localhost|g' > ${get_repo_root()}/.kubeconfig-ministack && echo '✓ ministack kubeconfig ready' || true"
    ]
    run_on_error = false
  }

  after_hook "gen_kubeconfig_aws" {
    commands     = ["apply"]
    execute      = ["bash", "-c",
      "aws eks update-kubeconfig --name terragrunt-infra-eks --region ap-southeast-1 2>/dev/null && echo '✓ aws kubeconfig ready' || true"
    ]
    run_on_error = false
  }
}
```

- [ ] **Step 2: Verify hook syntax parses**

```bash
cd units/eks && terragrunt validate-inputs 2>&1 | grep -i error | head -5
# should return nothing
```

- [ ] **Step 3: Commit**

```bash
git add units/eks/terragrunt.hcl
git commit -m "feat: auto-generate kubeconfig after eks apply for both ministack and aws"
```

---

## Task 4: Vault unit — auto-init + SSM token storage

**Files:**
- Modify: `units/vault/variables.tf`
- Modify: `units/vault/main.tf`
- Modify: `units/vault/outputs.tf`
- Modify: `units/vault/terragrunt.hcl`

- [ ] **Step 1: Add variables to units/vault/variables.tf**

```hcl
variable "region" {
  description = "AWS region"
  type        = string
}

variable "kms_key_id" {
  description = "KMS key ID for Vault auto-unseal"
  type        = string
}

variable "replicas" {
  description = "Number of Vault server replicas"
  type        = number
  default     = 3
}

variable "vault_sa_annotations" {
  description = "Annotations for Vault service account (e.g., IRSA role ARN)"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "use_ministack" {
  description = "Running against MiniStack (localstack)"
  type        = bool
  default     = false
}

variable "ssm_endpoint" {
  description = "SSM endpoint override for MiniStack"
  type        = string
  default     = ""
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig used by kubectl in init null_resource"
  type        = string
}
```

- [ ] **Step 2: Add init null_resource + SSM data source to units/vault/main.tf**

Append after `helm_release.vault_secrets_operator`:

```hcl
locals {
  vault_nodeport    = 30820
  ssm_token_name   = "/terragrunt-infra/vault/root-token"
  ssm_endpoint_arg = var.ssm_endpoint != "" ? "--endpoint-url ${var.ssm_endpoint}" : ""
}

resource "null_resource" "vault_init" {
  depends_on = [helm_release.vault, helm_release.vault_secrets_operator]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
    command = <<-EOF
      set -euo pipefail

      echo "Waiting for Vault pods..."
      kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=vault \
        -n vault --timeout=300s

      # Port-forward vault (use high port to avoid conflicts)
      kubectl port-forward svc/vault 18200:8200 -n vault &
      PF_PID=$!
      trap "kill $PF_PID 2>/dev/null || true" EXIT
      sleep 5

      export VAULT_ADDR="http://127.0.0.1:18200"

      INITIALIZED=$(vault status -format=json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['initialized'])" 2>/dev/null || echo "false")

      if [ "$INITIALIZED" = "False" ] || [ "$INITIALIZED" = "false" ]; then
        echo "Initializing Vault..."
        INIT_JSON=$(vault operator init \
          -recovery-shares=1 \
          -recovery-threshold=1 \
          -format=json)

        ROOT_TOKEN=$(echo "$INIT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['root_token'])")

        echo "Storing root token in SSM..."
        AWS_ACCESS_KEY_ID="${var.use_ministack ? "test" : ""}" \
        AWS_SECRET_ACCESS_KEY="${var.use_ministack ? "test" : ""}" \
        AWS_DEFAULT_REGION="${var.region}" \
        aws ssm put-parameter \
          --name "${local.ssm_token_name}" \
          --value "$ROOT_TOKEN" \
          --type SecureString \
          --overwrite \
          ${local.ssm_endpoint_arg}

        echo "Vault initialized and root token stored."
      else
        echo "Vault already initialized, skipping."
      fi
    EOF
  }

  triggers = {
    vault_helm_version = helm_release.vault.metadata[0].app_version
  }
}

data "aws_ssm_parameter" "vault_root_token" {
  name            = local.ssm_token_name
  with_decryption = true

  depends_on = [null_resource.vault_init]
}
```

- [ ] **Step 3: Update units/vault/outputs.tf**

```hcl
output "vault_address" {
  description = "Vault internal cluster address"
  value       = "http://vault.vault.svc.cluster.local:8200"
}

output "vault_namespace" {
  description = "Kubernetes namespace for Vault"
  value       = "vault"
}

output "vault_root_token" {
  description = "Vault root token (retrieved from SSM after auto-init)"
  value       = data.aws_ssm_parameter.vault_root_token.value
  sensitive   = true
}
```

- [ ] **Step 4: Update units/vault/terragrunt.hcl**

```hcl
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "k8s" {
  path   = "${get_repo_root()}/_common/k8s_providers.hcl"
  expose = true
}

locals {
  common  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  env_cfg = include.root.locals.env_cfg
}

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    vault_unseal_key_id = "mock-key-id"
  }
}

inputs = {
  region          = local.common.locals.region
  kms_key_id      = dependency.kms.outputs.vault_unseal_key_id
  replicas        = 3
  tags            = local.common.locals.common_tags
  use_ministack   = local.env_cfg.locals.use_ministack
  ssm_endpoint    = local.env_cfg.locals.use_ministack ? local.env_cfg.locals.endpoint : ""
  kubeconfig_path = local.env_cfg.locals.use_ministack ? "${get_repo_root()}/.kubeconfig-ministack" : pathexpand("~/.kube/config")
}
```

- [ ] **Step 5: Commit**

```bash
git add units/vault/
git commit -m "feat: vault auto-init with SSM root token storage"
```

---

## Task 5: Certs unit — use vault_token from dependency

**Files:**
- Modify: `units/certs/variables.tf`
- Modify: `units/certs/main.tf`
- Modify: `units/certs/terragrunt.hcl`

- [ ] **Step 1: Add vault_token to units/certs/variables.tf**

```hcl
variable "vault_address" {
  description = "Vault server address"
  type        = string
}

variable "vault_token" {
  description = "Vault root token for provider auth"
  type        = string
  sensitive   = true
}

variable "organization" {
  description = "Organization name for CA subject"
  type        = string
  default     = "HashiCorp Demo"
}
```

- [ ] **Step 2: Update provider block in units/certs/main.tf**

Replace the existing provider block at top of file:

```hcl
provider "vault" {
  address = var.vault_address
  token   = var.vault_token
}
```

(Keep all existing PKI resources unchanged below it.)

- [ ] **Step 3: Update units/certs/terragrunt.hcl**

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "vault" {
  config_path = "../vault"

  mock_outputs = {
    vault_address    = "http://vault.vault.svc.cluster.local:8200"
    vault_root_token = "mock-token"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  vault_address = dependency.vault.outputs.vault_address
  vault_token   = dependency.vault.outputs.vault_root_token
  organization  = "HashiCorp Demo"
}
```

- [ ] **Step 4: Commit**

```bash
git add units/certs/
git commit -m "feat: certs unit reads vault token from vault dependency output"
```

---

## Task 6: Vault-config unit — vault_token + rotate-root

**Files:**
- Modify: `units/vault-config/variables.tf`
- Modify: `units/vault-config/main.tf`
- Modify: `units/vault-config/terragrunt.hcl`

- [ ] **Step 1: Update units/vault-config/variables.tf**

```hcl
variable "vault_address" {
  description = "Vault server address"
  type        = string
}

variable "vault_token" {
  description = "Vault root token for provider auth"
  type        = string
  sensitive   = true
}

variable "kubernetes_host" {
  description = "Kubernetes API server URL"
  type        = string
}

variable "kubernetes_ca_cert" {
  description = "Kubernetes CA certificate (base64 decoded)"
  type        = string
  default     = ""
}

variable "rds_endpoint" {
  description = "RDS endpoint (host:port)"
  type        = string
}

variable "rds_username" {
  description = "RDS master username"
  type        = string
}

variable "rds_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "payments_processor_password" {
  description = "Static password for payments-processor"
  type        = string
  sensitive   = true
  default     = "changeme"
}

variable "ssm_endpoint" {
  description = "SSM endpoint override for MiniStack"
  type        = string
  default     = ""
}

variable "use_ministack" {
  description = "Running against MiniStack"
  type        = bool
  default     = false
}
```

- [ ] **Step 2: Update provider block + add rotate-root in units/vault-config/main.tf**

Replace the existing provider block:

```hcl
provider "vault" {
  address = var.vault_address
  token   = var.vault_token
}
```

Append at end of file after all existing resources:

```hcl
locals {
  ssm_token_name   = "/terragrunt-infra/vault/root-token"
  ssm_endpoint_arg = var.ssm_endpoint != "" ? "--endpoint-url ${var.ssm_endpoint}" : ""
}

resource "null_resource" "rotate_db_root" {
  depends_on = [vault_database_secret_backend_connection.postgres]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOF
      export VAULT_ADDR="${var.vault_address}"
      export VAULT_TOKEN="${var.vault_token}"

      kubectl port-forward svc/vault 18201:8200 -n vault &
      PF_PID=$!
      trap "kill $PF_PID 2>/dev/null || true" EXIT
      sleep 3

      export VAULT_ADDR="http://127.0.0.1:18201"
      vault write -force payments-app/database/rotate-root/payments
      echo "✓ DB root credentials rotated — bootstrap password invalidated"
    EOF
    environment = {
      KUBECONFIG = var.use_ministack ? pathexpand("~/.kube/config") : pathexpand("~/.kube/config")
    }
  }

  triggers = {
    connection_id = vault_database_secret_backend_connection.postgres.id
  }
}
```

- [ ] **Step 3: Update units/vault-config/terragrunt.hcl**

```hcl
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  env_cfg = include.root.locals.env_cfg
}

dependency "vault" {
  config_path = "../vault"

  mock_outputs = {
    vault_address    = "http://vault.vault.svc.cluster.local:8200"
    vault_root_token = "mock-token"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_endpoint                   = "https://mock"
    cluster_certificate_authority_data = "bW9jaw=="
  }
}

dependency "rds" {
  config_path = "../rds"

  mock_outputs = {
    rds_endpoint = "mock:5432"
    rds_username = "postgres"
  }
}

inputs = {
  vault_address   = dependency.vault.outputs.vault_address
  vault_token     = dependency.vault.outputs.vault_root_token
  kubernetes_host = dependency.eks.outputs.cluster_endpoint
  kubernetes_ca_cert = base64decode(
    dependency.eks.outputs.cluster_certificate_authority_data
  )
  rds_endpoint = dependency.rds.outputs.rds_endpoint
  rds_username = dependency.rds.outputs.rds_username
  rds_password = get_env("RDS_MASTER_PASSWORD", "")

  payments_processor_password = get_env("PAYMENTS_PROCESSOR_PASSWORD", "changeme")

  use_ministack = local.env_cfg.locals.use_ministack
  ssm_endpoint  = local.env_cfg.locals.use_ministack ? local.env_cfg.locals.endpoint : ""
}
```

- [ ] **Step 4: Commit**

```bash
git add units/vault-config/
git commit -m "feat: vault-config uses vault token from dependency, rotates db root after setup"
```

---

## Task 7: Trim vault-consul stack

**Files:**
- Modify: `stacks/vault-consul/terragrunt.stack.hcl`

Remove consul, datadog, flagger — these move to ArgoCD.

- [ ] **Step 1: Replace stacks/vault-consul/terragrunt.stack.hcl**

```hcl
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

# ── Layer 4: Data + Vault ────────────────────────────────────────

unit "rds" {
  source = "../../units/rds"
  path   = "rds"
}

unit "vault" {
  source = "../../units/vault"
  path   = "vault"
}

# ── Layer 5: Vault Config + PKI ──────────────────────────────────
# Depends on vault being initialized (handled by vault unit null_resource)

unit "certs" {
  source = "../../units/certs"
  path   = "certs"
}

unit "vault_config" {
  source = "../../units/vault-config"
  path   = "vault-config"
}

# ── Layer 6: ArgoCD Bootstrap ────────────────────────────────────

unit "argocd" {
  source = "../../units/argocd"
  path   = "argocd"

  values = {
    enable_consul_project = true
  }
}
```

- [ ] **Step 2: Verify no orphaned dependencies**

```bash
cd stacks/vault-consul && terragrunt stack generate 2>&1 | grep -i error | head -10
# should return nothing
```

- [ ] **Step 3: Commit**

```bash
git add stacks/vault-consul/terragrunt.stack.hcl
git commit -m "refactor: trim vault-consul stack — consul/datadog/flagger move to argocd"
```

---

## Task 8: Create gitops/values/ for platform apps

**Files:**
- Create: `gitops/values/consul.yaml`
- Create: `gitops/values/datadog.yaml`
- Create: `gitops/values/flagger.yaml`

- [ ] **Step 1: Create gitops/values/consul.yaml**

```yaml
global:
  name: consul
  datacenter: dc1
  acls:
    manageSystemACLs: true
  tls:
    enabled: true
  metrics:
    enabled: true
    enableAgentMetrics: true

server:
  enabled: true
  replicas: 3
  storage: 10Gi

client:
  enabled: true

connectInject:
  enabled: true
  default: true
  transparentProxy:
    defaultEnabled: true

apiGateway:
  enabled: true
  managedGatewayClass:
    serviceType: LoadBalancer

terminatingGateways:
  enabled: true
  defaults:
    replicas: 1
  gateways:
    - name: terminating-gateway

meshGateway:
  enabled: false

ui:
  enabled: true
  service:
    type: LoadBalancer
```

- [ ] **Step 2: Create gitops/values/datadog.yaml**

```yaml
datadog:
  site: datadoghq.com
  logs:
    enabled: true
    containerCollectAll: true
  apm:
    enabled: true
  processAgent:
    enabled: true
  kubelet:
    tlsVerify: false

clusterAgent:
  enabled: true
  metricsProvider:
    enabled: true
```

- [ ] **Step 3: Create gitops/values/flagger.yaml**

```yaml
meshProvider: consul
metricsServer: http://prometheus-server.default:9090

podMonitor:
  enabled: false

prometheus:
  install: false

slack:
  url: ""
  channel: ""
```

- [ ] **Step 4: Commit**

```bash
git add gitops/values/
git commit -m "feat: add gitops helm values for consul, datadog, flagger"
```

---

## Task 9: Create gitops/appset.yaml

**Files:**
- Create: `gitops/appset.yaml`

- [ ] **Step 1: Create gitops/appset.yaml**

Replace `YOUR_REPO_URL` with actual git repo URL before applying.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: platform
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          # ── Wave 1: Service Mesh ──────────────────────────────
          - app: consul
            repoURL: https://helm.releases.hashicorp.com
            chart: consul
            targetRevision: "1.4.*"
            namespace: consul
            wave: "1"
            valuesFile: ""
            inlineValues: "true"

          # ── Wave 2: Infrastructure controllers ───────────────
          - app: aws-alb
            repoURL: https://aws.github.io/eks-charts
            chart: aws-load-balancer-controller
            targetRevision: "*"
            namespace: kube-system
            wave: "2"
            valuesFile: ""
            inlineValues: "false"

          - app: datadog
            repoURL: https://helm.datadoghq.com
            chart: datadog
            targetRevision: "*"
            namespace: datadog
            wave: "2"
            valuesFile: ""
            inlineValues: "true"

          # ── Wave 3: Progressive Delivery ─────────────────────
          - app: flagger
            repoURL: https://flagger.app
            chart: flagger
            targetRevision: "*"
            namespace: flagger-system
            wave: "3"
            valuesFile: ""
            inlineValues: "true"

  template:
    metadata:
      name: "{{app}}"
      namespace: argocd
      annotations:
        argocd.argoproj.io/sync-wave: "{{wave}}"
    spec:
      project: default
      source:
        repoURL: "{{repoURL}}"
        chart: "{{chart}}"
        targetRevision: "{{targetRevision}}"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{namespace}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
---
# payments-app deployed from this git repo (Helm chart in gitops/charts/)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: payments-app
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "4"
spec:
  project: payments-app
  source:
    repoURL: YOUR_REPO_URL
    targetRevision: main
    path: gitops/charts/payments-app
    helm:
      valueFiles:
        - values/vault-consul.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: payments-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

- [ ] **Step 2: Set consul, datadog, flagger values from gitops/values/**

The ApplicationSet above uses inline values for consul/datadog/flagger. Update to reference value files from this repo by changing the ApplicationSet to a git-sourced multi-source approach. Replace the list generator template's `source` block:

```yaml
  template:
    metadata:
      name: "{{app}}"
      namespace: argocd
      annotations:
        argocd.argoproj.io/sync-wave: "{{wave}}"
    spec:
      project: default
      sources:
        - repoURL: "{{repoURL}}"
          chart: "{{chart}}"
          targetRevision: "{{targetRevision}}"
          helm:
            valueFiles:
              - $values/gitops/values/{{app}}.yaml
        - repoURL: YOUR_REPO_URL
          targetRevision: main
          ref: values
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{namespace}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

Remove `inlineValues` fields from list elements since values come from files now.

- [ ] **Step 3: Commit**

```bash
git add gitops/appset.yaml
git commit -m "feat: add argocd applicationset for platform apps (consul/datadog/flagger/payments-app)"
```

---

## Task 10: Update Makefile

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Replace STACKS_MAP, UNIT_LIST, HELM_VALUES**

```makefile
STACKS_MAP := vault:vault-consul

UNIT_LIST := vpc eks kms rds vault consul argocd flagger datadog aws-alb

HELM_VALUES := vault:vault-consul
```

- [ ] **Step 2: Remove sops/linkerd-specific targets**

Delete these entire blocks:
- `helm sops` variant (keep `helm vault` only)
- `helm-template sops` variant
- `graph-sops` target
- `stack-sops` (already removed via STACKS_MAP change)

- [ ] **Step 3: Update clean-all**

```makefile
.PHONY: clean-all
clean-all: clean-helm
	cd $(STACKS)/vault-consul && terragrunt stack run destroy $(TG_FLAGS) || true
```

- [ ] **Step 4: Add gitops-bootstrap target**

```makefile
GITOPS_DIR := gitops

.PHONY: gitops-bootstrap
gitops-bootstrap:
	@echo "Bootstrapping ArgoCD ApplicationSet..."
	@KUBECONFIG=$(MINISTACK_KUBECONFIG) kubectl apply -f $(GITOPS_DIR)/appset.yaml
	@echo "✓ ArgoCD ApplicationSet applied — ArgoCD will sync apps"

.PHONY: vault-rotate-db
vault-rotate-db:
	@echo "Rotating Vault DB root credentials..."
	@VAULT_ADDR=http://vault.vault.svc.cluster.local:8200 \
		kubectl port-forward svc/vault 18202:8200 -n vault & \
		sleep 3 && \
		VAULT_ADDR=http://127.0.0.1:18202 vault write -force payments-app/database/rotate-root/payments && \
		echo "✓ DB root credentials rotated"
```

- [ ] **Step 5: Update ms-init message**

```makefile
.PHONY: ms-init
ms-init: ms-up ms-enable ms-seed
	@echo ""
	@echo "══════════════════════════════════════════════════"
	@echo "  MiniStack local environment is ready!"
	@echo "  Run: make stack-vault apply"
	@echo "  Then: make gitops-bootstrap"
	@echo "══════════════════════════════════════════════════"
```

- [ ] **Step 6: Verify Makefile has no sops references**

```bash
grep -n "sops" Makefile
# should return nothing
```

- [ ] **Step 7: Commit**

```bash
git add Makefile
git commit -m "refactor: remove sops from makefile, add gitops-bootstrap and vault-rotate-db targets"
```

---

## Task 11: End-to-end smoke test (ministack)

- [ ] **Step 1: Start ministack**

```bash
make ms-init
# Expected: ✓ MiniStack is ready on http://localhost:4566
```

- [ ] **Step 2: Apply vault-consul stack**

```bash
RDS_MASTER_PASSWORD=postgres123 make stack-vault apply
# Expected (in order):
#   vpc → eks → ✓ ministack kubeconfig ready
#   kms → rds → vault → Vault initialized and root token stored
#   certs → vault-config → ✓ DB root credentials rotated
#   argocd → Apply complete!
```

- [ ] **Step 3: Verify kubeconfig generated**

```bash
ls -la .kubeconfig-ministack
kubectl --kubeconfig=.kubeconfig-ministack get nodes
# Expected: ministack-eks-terragrunt-infra-eks   Ready
```

- [ ] **Step 4: Verify Vault initialized**

```bash
kubectl --kubeconfig=.kubeconfig-ministack get pods -n vault
# Expected: vault-0   1/1   Running
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
  aws --endpoint-url http://localhost:4566 ssm get-parameter \
  --name /terragrunt-infra/vault/root-token --with-decryption \
  --query Parameter.Value --output text
# Expected: s.xxxxxxxxxxxx (vault token, not empty)
```

- [ ] **Step 5: Verify ArgoCD running**

```bash
kubectl --kubeconfig=.kubeconfig-ministack get pods -n argocd
# Expected: argocd-server, argocd-repo-server, argocd-application-controller running
```

- [ ] **Step 6: Bootstrap ArgoCD ApplicationSet**

```bash
make gitops-bootstrap
# Expected: applicationset.argoproj.io/platform created
#           application.argoproj.io/payments-app created
```

- [ ] **Step 7: Watch ArgoCD sync waves**

```bash
kubectl --kubeconfig=.kubeconfig-ministack get applications -n argocd -w
# Expected (in order):
#   consul         Syncing → Synced
#   aws-alb        Syncing → Synced
#   datadog        Syncing → Synced
#   flagger        Syncing → Synced
#   payments-app   Syncing → Synced
```

- [ ] **Step 8: Final commit**

```bash
git add -A
git commit -m "chore: verify vault gitops migration end-to-end"
```
