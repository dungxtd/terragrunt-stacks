# Production Flow Guide

How platform actually behaves in production. Diagrams + sequences per use case. No code, no theory.

---

## System at a Glance

```mermaid
flowchart TB
  subgraph "Developer"
    GIT[git push]
  end

  subgraph "GitHub Actions"
    DEPLOY[Deploy Infrastructure]
    GITOPS[Deploy GitOps]
  end

  subgraph "AWS"
    EKS[EKS cluster]
    VAULT[Vault HA]
    RDS[(RDS Postgres)]
    KMS[KMS]
    ALB[ALBs]
    SSM[SSM Parameter Store]
  end

  subgraph "ArgoCD - in EKS"
    ROOT[App-of-Apps root]
    PROJECT[AppProject platform]
    APPS[child Applications]
  end

  subgraph "Runtime - in EKS"
    ESO[ExternalSecrets Operator]
    PAY[payments-app pods]
    DD[datadog]
    FLAG[flagger canary]
    LINK[linkerd mesh]
  end

  GIT --> DEPLOY
  GIT --> GITOPS
  DEPLOY -->|terragrunt apply| EKS
  DEPLOY -->|terragrunt apply| VAULT
  DEPLOY -->|terragrunt apply| RDS
  GITOPS -.->|waits for deploy| DEPLOY
  GITOPS -->|kubectl apply root.yaml| ROOT
  ROOT --> PROJECT
  ROOT --> APPS
  APPS --> ESO
  APPS --> PAY
  APPS --> DD
  APPS --> FLAG
  ESO -->|reads secrets| VAULT
  ESO -->|writes k8s Secret| DD
  PAY -->|Vault Agent inject| VAULT
  PAY -->|RDS dynamic creds| RDS
  PAY <-->|sidecar mTLS| LINK
  VAULT -->|auto-unseal| KMS
  VAULT -->|recovery keys backup| SSM
  ALB -->|routes /| PAY
  ALB -->|routes /argocd| ROOT
```

---

## Cold Start — Bootstrap from Empty AWS Account

```mermaid
sequenceDiagram
  autonumber
  actor Dev
  participant CI as GitHub Actions
  participant TG as Terragrunt
  participant AWS
  participant K as EKS
  participant Argo as ArgoCD

  Dev->>CI: git push (initial commit)
  CI->>TG: deploy.yml apply
  TG->>AWS: VPC, EKS, KMS, RDS
  TG->>K: install Vault, ArgoCD, Linkerd, ALB controller
  TG->>K: configure Vault auth roles + policies
  CI->>Argo: gitops.yml apply gitops/apps/root.yaml
  Argo->>Argo: reconcile App-of-Apps
  Argo->>K: create AppProject (wave -10)
  Argo->>K: install ExternalSecrets controller (wave 0)
  Argo->>K: ClusterSecretStore + ExternalSecrets (wave 1)
  Argo->>K: consul, datadog, flagger (waves 1-3)
  Argo->>K: payments-app (wave 4)
  Argo->>K: ingresses (wave 5)
  K->>AWS: ALB controller provisions ALBs
  Argo-->>Dev: all apps Synced + Healthy
```

**Observable**: ~10 min cold start, ~3 min warm. `kubectl get applications -n argocd` shows all `Synced/Healthy`.

---

## Daily Use Case 1: Push GitOps-Only Change

You change a Helm value (e.g. bump replica count, rotate chart version, add Ingress).

```mermaid
sequenceDiagram
  autonumber
  actor Dev
  participant GH as GitHub
  participant CI as gitops.yml
  participant Argo as ArgoCD
  participant K as EKS

  Dev->>GH: push (only gitops/** changed)
  GH->>CI: trigger gitops.yml (path match)
  Note over GH: deploy.yml NOT triggered (paths exclude gitops/)
  CI->>K: kubectl apply gitops/apps/root.yaml (idempotent)
  Argo-->>Argo: detects git change in gitops/values/
  Argo->>K: re-render Helm chart, apply diff
  K-->>Argo: resources updated (rolling)
  Argo-->>Dev: app shows Synced
```

**Observable**: ~30s pipeline + ~1-3min ArgoCD reconcile. No infra apply.

---

## Daily Use Case 2: Push Terraform-Only Change

You change `units/<name>/` or `stacks/<env>/env.hcl` (e.g. EKS node size, RDS class).

```mermaid
sequenceDiagram
  autonumber
  actor Dev
  participant GH as GitHub
  participant CI as deploy.yml
  participant TG as Terragrunt
  participant AWS
  participant CIB as gitops.yml

  Dev->>GH: push (only units/** or stacks/** changed)
  GH->>CI: trigger deploy.yml
  CI->>TG: validate + plan + apply
  TG->>AWS: apply changes per unit
  AWS-->>CI: success
  GH->>CIB: trigger gitops.yml via workflow_run
  CIB-->>CIB: re-applies root.yaml (no-op, repo unchanged)
  Note over CIB: idempotent — ArgoCD picks up any new TF outputs on next reconcile
```

**Observable**: ~5-10min pipeline. ArgoCD apps unchanged.

---

## Daily Use Case 3: Push Touches BOTH Layers

You add a new Vault role (TF) AND a new ExternalSecret consuming it (gitops). Race risk: gitops applies before TF creates the role → ESO `permission denied`.

```mermaid
sequenceDiagram
  autonumber
  actor Dev
  participant GH as GitHub
  participant DEPLOY as deploy.yml
  participant GITOPS as gitops.yml
  participant Argo as ArgoCD

  Dev->>GH: push (both units/ + gitops/)
  GH->>DEPLOY: trigger (units/ path match)
  GH->>GITOPS: trigger via push event (parallel run #1)
  par Parallel
    DEPLOY->>DEPLOY: apply Vault TF (creates role)
  and
    GITOPS->>Argo: apply root.yaml
    Argo-->>Argo: ESO retries Vault auth (role missing)
  end
  DEPLOY-->>GH: success
  GH->>GITOPS: trigger via workflow_run (run #2, after deploy)
  GITOPS->>Argo: apply root.yaml again (idempotent)
  Argo-->>Argo: ESO retry succeeds (role now exists)
  Argo-->>Dev: all Synced
```

**Observable**: brief `permission denied` in ESO logs, self-heals within 1-2 min after deploy completes. **No manual intervention.**

---

## Use Case 4: Add a New Microservice

```mermaid
flowchart LR
  A["Edit gitops/values/payments-app/production.yaml<br/>add to services: map"] --> B[git push]
  B --> C[gitops.yml fires]
  C --> D[ArgoCD re-renders chart]
  D --> E[lib.workload generates<br/>Deployment + Service]
  E --> F[k8s creates pods]
  F --> G[linkerd injects sidecar]
  G --> H[Ready]
```

**You write**: ~10 lines in values file.
**You wait**: ~2 min.
**Done**.

---

## Use Case 5: Add a New Secret

```mermaid
sequenceDiagram
  autonumber
  actor Op as Operator
  participant V as Vault
  participant Dev
  participant Git
  participant Argo as ArgoCD
  participant ESO
  participant K as EKS

  Op->>V: vault kv put secret/foo/bar key=val (one-time)
  Dev->>Git: edit gitops/values/secret-stores/production.yaml<br/>add entry under externalSecrets:
  Dev->>Git: git push
  Git->>Argo: gitops.yml triggers reconcile
  Argo->>K: ExternalSecret CR created
  ESO->>V: read secret/foo/bar (auth via SA token)
  ESO->>K: create Secret/foo in target namespace
  K-->>Dev: kubectl get secret foo → exists
```

**Default**: all Vault fields → all Secret keys (no mapping needed).
**On Vault rotation**: ESO refreshes within 1h, Secret updates, consumers re-read.

---

## Use Case 6: Rotate a Secret (Zero Downtime)

```mermaid
sequenceDiagram
  autonumber
  actor Op as Operator
  participant V as Vault
  participant ESO
  participant K as EKS
  participant Pod as Consumer Pod

  Op->>V: vault kv put secret/foo/bar key=NEW_VAL
  Note over ESO: refreshInterval = 1h<br/>(force immediate via annotation)
  ESO->>V: scheduled read
  ESO->>K: update Secret/foo (data changed)
  Op->>K: kubectl rollout restart deploy/<consumer>
  K->>Pod: new pod with new env value
  Pod-->>Op: serves traffic with new key
```

**No git push, no CI run.** Pure runtime operation.

---

## Use Case 7: Bump an Upstream Chart Version

```mermaid
flowchart LR
  A["Edit gitops/apps/appset-platform.yaml<br/>targetRevision: 3.205.0 -> 3.206.0"] --> B[git push]
  B --> C[gitops.yml fires]
  C --> D[ArgoCD pulls new chart from upstream Helm repo]
  D --> E[Re-render with same values]
  E --> F{Diff vs live?}
  F -->|safe| G[Auto-sync, rolling update]
  F -->|breaking| H[Status: OutOfSync<br/>Health: Degraded]
  H --> I[git revert<br/>OR<br/>fix values + re-push]
```

**Observable**: chart bump appears in ArgoCD UI as 1 commit diff.

---

## Use Case 8: Pod Crashes (Self-Heal)

```mermaid
sequenceDiagram
  autonumber
  participant Pod
  participant K as EKS
  participant Argo as ArgoCD

  Pod->>Pod: OOMKilled
  K->>K: ReplicaSet creates new pod
  K-->>Pod: pod Running again
  Note over Argo: ArgoCD selfHeal continuously watches<br/>desired = git, live = cluster
  Argo-->>K: no diff → no action
```

**No human in loop**. k8s ReplicaSet handles. ArgoCD only intervenes if cluster state DRIFTS from git (someone `kubectl edit`s).

If someone `kubectl scale deploy/payments-app --replicas=10`:
```mermaid
sequenceDiagram
  participant Op as Operator
  participant K as EKS
  participant Argo as ArgoCD
  Op->>K: kubectl scale --replicas=10
  Argo-->>Argo: detects drift (git=1, live=10)
  Argo->>K: revert to replicas=1
  Note over Argo: payments-app has ignoreDifferences for /spec/replicas<br/>(Flagger owns this) — so above scale would be allowed
```

---

## Use Case 9: ArgoCD App Stuck OutOfSync

Common causes: immutable Job spec changed, helm-managed annotations differ from server-side defaults.

```mermaid
flowchart TB
  A[App OutOfSync] --> B{Cause?}
  B -->|Immutable resource<br/>Job/Service nodePort| C[kubectl delete resource]
  C --> D[ArgoCD recreates with current spec]
  B -->|Helm checksum drift| E[Add ignoreDifferences<br/>in apps yaml]
  B -->|Stale cache| F[kubectl annotate<br/>refresh=hard]
  D --> G[Synced]
  E --> G
  F --> G
```

Runbooks: [`runbooks/`](runbooks/) — canary stuck, consul stale services.

---

## Use Case 10: Rollback a Bad Deploy

```mermaid
sequenceDiagram
  autonumber
  actor Dev
  participant Git
  participant Argo
  participant K

  Dev->>Argo: notices payments-app crashloop after sync
  Dev->>Git: git revert <bad-sha>
  Dev->>Git: git push
  Git->>Argo: gitops.yml fires
  Argo->>K: re-renders chart at previous values
  K-->>Argo: pods rollback (rolling)
  Argo-->>Dev: Synced + Healthy
```

**Recovery time**: ~3 min from `git push` to all pods Healthy.

For TF rollback: same flow, `git revert` → `deploy.yml` re-applies prior infra.

---

## Use Case 11: Migrate Vault dev → HA (Planned Maintenance)

⚠️ Destructive. Plan downtime window.

```mermaid
sequenceDiagram
  autonumber
  actor Op as Operator
  participant V as Vault dev
  participant TG as Terragrunt
  participant V2 as Vault HA<br/>(3 replicas, Raft, KMS unseal)
  participant SSM
  participant Apps as Consumers

  Op->>V: backup all secrets (vault kv get -format=json)
  Op->>Op: verify env.hcl: vault_mode = ha
  Op->>TG: terragrunt destroy units/vault-config + vault
  TG->>V: tear down dev pod
  Op->>TG: terragrunt apply units/vault
  TG->>V2: 3 pods boot, Raft elects leader
  V2->>V2: KMS auto-unseal (no manual keys)
  TG->>V2: vault operator init -recovery-shares=5 -recovery-threshold=3
  TG->>SSM: stash root + recovery keys (encrypted)
  Op->>TG: apply units/vault-config (re-create roles/policies)
  Op->>V2: vault kv put (restore secrets from backup)
  Op->>Apps: kubectl rollout restart all consumers
  Apps-->>Op: re-auth, re-fetch secrets, healthy
```

**Test in MiniStack first.** Detailed steps: [`runbooks/vault-ha-migration.md`](runbooks/vault-ha-migration.md).

---

## Use Case 12: Datadog API Key Missing (Today's Bug)

```mermaid
flowchart LR
  A[datadog cluster-agent<br/>logs: API Key invalid 403] --> B{Cause}
  B --> C[Secret/datadog<br/>has no api-key field]
  C --> D[Operator: vault kv put<br/>secret/datadog/api api-key=...]
  D --> E[ESO refresh within 1h<br/>OR force-sync annotation]
  E --> F[Secret/datadog populated]
  F --> G[kubectl rollout restart<br/>datadog-cluster-agent]
  G --> H[403 errors stop]
```

---

## Use Case 13: ALB Controller Upgrade

```mermaid
sequenceDiagram
  autonumber
  actor Op as Operator
  participant K as EKS
  participant CI
  participant TG
  participant LBC as ALB Controller

  Op->>K: make alb-crds (apply CRDs first)
  Op->>K: edit units/aws-alb/main.tf chart version
  Op->>CI: git push
  CI->>TG: deploy.yml runs terragrunt apply
  TG->>LBC: helm upgrade to new version
  LBC->>LBC: new pod replaces old (rolling)
  LBC-->>K: existing ALBs continue serving (no flap)
```

**Critical**: CRDs first, chart second. Helm doesn't upgrade CRDs.

---

## Use Case 14: Local Dev (MiniStack)

```mermaid
flowchart LR
  A[make ms-bootstrap] --> B[docker compose up<br/>LocalStack + k3s]
  B --> C[seed S3 + DynamoDB lock table]
  C --> D[terragrunt stack apply<br/>against LocalStack endpoints]
  D --> E[kubectl apply gitops/apps/root.yaml<br/>against k3s]
  E --> F[ArgoCD reconciles all apps locally]
  F --> G[source scripts/load_env.sh ministack<br/>to interact]
```

**Identical** to production flow. Same Helm charts, same Vault setup, same App-of-Apps. Only env.hcl differs (LocalStack endpoint, no NAT, no github-runner).

**Cost**: $0 + 4-8GB RAM.

---

## Use Case 15: Pipeline Failure Recovery

```mermaid
flowchart TB
  A[deploy.yml failed] --> B{Failure type}
  B -->|TF error<br/>e.g. AWS quota| C[fix in code, re-push]
  B -->|state lock| D[wait for lock TTL<br/>OR force-unlock manually]
  B -->|partial apply| E[re-run deploy.yml<br/>terragrunt is idempotent]

  F[gitops.yml failed] --> G{Failure type}
  G -->|workflow_run skipped<br/>because deploy failed| H[fix deploy first<br/>workflow_run will trigger gitops]
  G -->|kubectl apply error| I[ArgoCD self-heals<br/>or manual kubectl apply]
  G -->|EKS unreachable| J[check cluster status<br/>aws eks describe-cluster]
```

---

## Use Case 16: Onboarding a New Developer

```mermaid
flowchart LR
  A[clone repo] --> B[install: terragrunt, terraform, kubectl, helm, docker]
  B --> C[make ms-bootstrap<br/>local stack ~4 min]
  C --> D[source scripts/load_env.sh ministack]
  D --> E[explore: make help / kubectl / argocd UI]
  E --> F[edit gitops/values/<app>/<env>.yaml<br/>see change locally]
  F --> G[git push branch → PR → CI runs plan only]
  G --> H[merge → main → CI applies]
```

---

## Decision Trees

### "I need to add X — where do I edit?"

```mermaid
flowchart TB
  X[Add new...] --> Y{What?}
  Y -->|microservice| MS[gitops/values/payments-app/production.yaml<br/>services: map]
  Y -->|secret| SEC[gitops/values/secret-stores/production.yaml<br/>externalSecrets: map<br/>+ vault kv put]
  Y -->|ingress| ING[gitops/platform/platform-ui/ingresses.yaml]
  Y -->|upstream Helm app<br/>e.g. prometheus| APP[2 files:<br/>gitops/apps/appset-platform.yaml elements list<br/>gitops/values/prometheus/production.yaml]
  Y -->|in-house Helm chart| CHART[gitops/charts/<name>/<br/>+ gitops/apps/<name>.yaml<br/>+ gitops/values/<name>/production.yaml]
  Y -->|Vault role/policy| VLT[units/vault-config/main.tf]
  Y -->|TF module| TF[units/<name>/<br/>+ stacks/<env>/terragrunt.stack.hcl]
  Y -->|env config<br/>NAT, replicas, mode| ENV[stacks/<family>/<env>/env.hcl]
  Y -->|CI step| CI[.github/workflows/<wf>.yml]
  Y -->|Make target| MK[makefiles/<area>.mk<br/>with ## help text]
```

### "Something broke — where do I look?"

```mermaid
flowchart TB
  X[Broken] --> Y{Symptom}
  Y -->|app pod crashlooping| A[kubectl logs + describe<br/>kubectl get events]
  Y -->|app OutOfSync in ArgoCD| B[kubectl describe app -n argocd<br/>+ runbooks/]
  Y -->|secret missing/wrong| C[kubectl get externalsecret -A<br/>+ vault kv list]
  Y -->|ALB not provisioned| D[kubectl logs -n kube-system<br/>aws-load-balancer-controller]
  Y -->|Vault sealed/unreachable| E[make vault-status<br/>+ kubectl logs vault-0]
  Y -->|pipeline failed| F[gh run list + gh run view --log-failed]
  Y -->|RDS connection error| G[check security groups<br/>+ vault dynamic creds TTL]
  Y -->|metrics missing| H[datadog logs for 403<br/>+ check Secret/datadog populated]
  Y -->|canary stuck| I[runbooks/canary-stuck.md<br/>(linkerd-smi check)]
```

---

## Authority Matrix

| Resource | Source of Truth | Mutator | Reconciler |
|----------|-----------------|---------|------------|
| AWS infra (VPC, EKS, RDS, IAM) | `units/<name>/` | CI (`deploy.yml`) | Terragrunt |
| Vault auth roles/policies | `units/vault-config/` | CI | Terragrunt |
| Vault secret values | Vault KV | Operator (manual `vault kv put`) | none — operator owns |
| ArgoCD Applications | `gitops/apps/` | CI (`gitops.yml`) | ArgoCD |
| Helm chart values | `gitops/values/<app>/<env>.yaml` | git → CI | ArgoCD |
| k8s Secrets | ExternalSecrets CR (rendered from values) | ESO controller | ESO |
| payments-app replicas | Flagger (canary) | Flagger | (ArgoCD ignores) |
| ALB instances | Ingress objects | ArgoCD | aws-load-balancer-controller |
| RDS dynamic DB users | Vault DB engine | payments-app pod request | Vault (TTL revoke) |

---

## Time-to-Recovery Cheatsheet

| Scenario | RTO |
|----------|-----|
| App pod crash | seconds (k8s ReplicaSet) |
| Drift (kubectl edit) | seconds (ArgoCD selfHeal) |
| Bad gitops push | ~3 min (revert + re-deploy) |
| Bad TF apply | ~10 min (revert + re-apply) |
| Datadog API key invalid | minutes (vault kv put + restart) |
| Vault dev pod restart (loses secrets) | minutes (re-put all secrets manually) |
| Vault HA pod restart | seconds (Raft + KMS auto-unseal) |
| EKS node failure | minutes (auto-replace via ASG) |
| Cluster lost | hours (full bootstrap from scratch) |

---

## See Also

- [`architecture.md`](architecture.md) — env topology + network/vault diagrams
- [`adr/`](adr/) — why decisions were made
- [`runbooks/`](runbooks/) — step-by-step fix recipes
- [`gitops/README.md`](../gitops/README.md) — GitOps deep dive
