# Architecture

## Table of Contents

- [Deployment Flow](#deployment-flow)
- [MiniStack (Local Dev)](#ministack-local-dev)
- [AWS (Production)](#aws-production)
- [Vault Secrets Flow](#vault-secrets-flow)

---

## Deployment Flow

```text
               stacks/vault-consul/<env>/env.hcl
               Each env.hcl is self-contained: provider, backend, feature flags.
                        │
                        ├─── ministack/env.hcl        production/env.hcl
                        │                              │
                        ▼                              ▼
               make ms-bootstrap              make stack-vault-production apply
               (auto → ministack dir)         + pipeline applies gitops & ingresses
```

### Terragrunt Stack Layers

```text
  Layer 1 ─── vpc ─────────────────────────────────── Network
                │
  Layer 2 ─── eks ─────────────────────────────────── Compute (k3s / EKS)
                │                │
  Layer 3 ─── kms ──┐           │ ─────────────────── Security
                     │           │
  Layer 4 ─── vault ─┘    ─── rds ────────────────── Data + Secrets
                │                │
  Layer 5 ─── certs      ─── vault-config ─────────── Vault PKI + Config
                │
  Layer 6 ─── linkerd     ─── argocd ─── aws-alb ── Platform + GitOps
                │
  Layer 7 ─── github-runner ───────────────────────── CI/CD (AWS only)
```

### GitOps Waves (ArgoCD ApplicationSet)

```text
  Wave 1 ─── consul ────────────────── Service mesh
  Wave 2 ─── datadog ────────────── Monitoring (aws-alb is Terraform-managed)
  Wave 3 ─── flagger ─────────────── Progressive delivery
  Wave 4 ─── payments-app ─────────── Application
```

---

## MiniStack (Local Dev)

### Overview

```text
  Environment:    ministack
  Config:         stacks/vault-consul/ministack/env.hcl
  Bootstrap:      make ms-bootstrap  (single command, ~4 min)
  Env vars:       source load_env.sh ministack
  Teardown:       make ms-teardown
```

### What's Different from AWS

| Resource | MiniStack | Why |
|----------|-----------|-----|
| AWS API | MiniStack container (emulated) | No real AWS account needed |
| EKS | k3s in Docker (host network) | Lightweight single-node cluster |
| RDS | Docker postgres:15 (port 15432) | Real PostgreSQL, not just API mock |
| Vault | Dev mode, root token = `root` | No auto-unseal, no HA needed |
| Linkerd certs | TLS provider (self-signed) | No Vault PKI, `external_ca=false` |
| GitHub Runner | Disabled (`count=0`) | No GitHub connectivity needed |
| State backend | MiniStack S3 + DynamoDB | Emulated, resets with `ms-reset` |
| ArgoCD | NodePort :30443 | No LoadBalancer in local k3s |

### Network Topology

```text
┌─── Mac Host ──────────────────────────────────────────────────────────┐
│                                                                        │
│  ┌─── Docker (OrbStack) ──────────────────────────────────────────┐   │
│  │                                                                 │   │
│  │  ┌─ ministack (:4566) ──────────────────────────────────────┐  │   │
│  │  │  MiniStack API server (Python/Hypercorn)                  │  │   │
│  │  │  Emulates: S3, DynamoDB, EC2, EKS, RDS, KMS, SSM, IAM    │  │   │
│  │  │                                                           │  │   │
│  │  │  On EKS create → spawns k3s container                    │  │   │
│  │  │  On RDS create → spawns postgres:15 container            │  │   │
│  │  └───────────┬──────────────────────────┬───────────────────┘  │   │
│  │              │                          │                       │   │
│  │              ▼                          ▼                       │   │
│  │  ┌─ k3s (host network) ─────────┐  ┌─ postgres:15 ─────────┐  │   │
│  │  │  container: ministack-eks-*   │  │  container: ministack- │  │   │
│  │  │  network: host                │  │  rds-*                 │  │   │
│  │  │                               │  │  network: bridge       │  │   │
│  │  │  Namespaces:                  │  │  IP: 172.18.0.3        │  │   │
│  │  │  ┌─ vault ──────────────┐    │  │  Port: 5432 → :15432   │  │   │
│  │  │  │  vault-0 (dev mode)  │    │  │                         │  │   │
│  │  │  │  vault-secrets-op    │    │  │  DB: payments            │  │   │
│  │  │  └──────────────────────┘    │  │  User: postgres          │  │   │
│  │  │  ┌─ argocd ─────────────┐    │  │  Pass: password          │  │   │
│  │  │  │  server (7 pods)     │    │  └─────────────────────────┘  │   │
│  │  │  └──────────────────────┘    │       ▲                       │   │
│  │  │  ┌─ linkerd ────────────┐    │       │                       │   │
│  │  │  │  identity            │    │       │ Vault connects via    │   │
│  │  │  │  destination         │    │       │ host.docker.internal  │   │
│  │  │  │  proxy-injector      │    │       │ :15432                │   │
│  │  │  └──────────────────────┘    │       │                       │   │
│  │  │  ┌─ linkerd-viz ────────┐    │       │                       │   │
│  │  │  │  prometheus, tap,    │    │       │                       │   │
│  │  │  │  metrics-api, web    │    │       │                       │   │
│  │  │  └──────────────────────┘    │       │                       │   │
│  │  └──────────────────────────────┘───────┘                       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                        │
│  Access from Mac:                                                      │
│  ─────────────────────────────────────────────────────                 │
│  Terragrunt  ──► localhost:4566  (MiniStack AWS API)                   │
│  kubectl     ──► localhost:6443  (.kubeconfig-ministack)               │
│  Vault       ──► localhost:18200 (kubectl port-forward)                │
│  ArgoCD UI   ──► localhost:30443 (NodePort)                            │
│  PostgreSQL  ──► localhost:15432 (Docker port mapping)                 │
└────────────────────────────────────────────────────────────────────────┘
```

### Bootstrap Sequence

```text
  make ms-bootstrap
    │
    ├─ 1. tg-clean ─────────── Remove .terragrunt-cache, .terraform
    ├─ 2. ms-reset ─────────── POST /_ministack/reset (wipe all state)
    ├─ 3. ms-seed ──────────── Create S3 bucket + DynamoDB lock table
    │
    ├─ 4. stack apply ─────── Terragrunt deploys 10 units:
    │     ├─ vpc              VPC + subnets (emulated)
    │     ├─ eks              k3s container + kubeconfig
    │     ├─ kms              KMS key (emulated)
    │     ├─ rds              postgres:15 container (real DB)
    │     ├─ vault            Helm: vault dev mode + secrets operator
    │     ├─ certs            Vault PKI backends (consul CAs)
    │     ├─ vault-config     K8s auth, Transit, DB secrets, KV v2
    │     ├─ linkerd          Helm: CRDs + control plane + viz
    │     ├─ argocd           Helm: ArgoCD (NodePort)
    │     └─ github-runner    SKIPPED (count=0)
    │
    ├─ 5. gitops-bootstrap ── kubectl apply appset.yaml
    │     └─ Creates: consul, aws-alb, datadog, flagger, payments-app
    │
    └─ 6. cleanup ─────────── Kill stale port-forwards
```

### Make Targets

```text
  make ms-bootstrap     Full bootstrap from scratch
  make ms-init          Start MiniStack + seed (no deploy)
  make ms-teardown      Stop MiniStack + switch to aws env
  make ms-reset         Wipe all MiniStack state
  make ms-status        Show MiniStack container health
  make ms-logs          Tail MiniStack container logs

  make stack-vault apply   Re-apply stack (idempotent)
  make vault-status        Vault health via curl
  make vault-db-creds      Generate dynamic DB credentials
  make vault-rotate-db     Rotate DB root password

  source load_env.sh       Export KUBECONFIG, VAULT_ADDR, ARGOCD_ADMIN_PASS, etc.
```

---

## AWS (Production)

### Overview

```text
  Environment:    production
  Config:         stacks/vault-consul/production/env.hcl
  Bootstrap:      make stack-vault-production apply  (pipeline auto-applies gitops + ingresses)
  Env vars:       source load_env.sh production
```

### What's Different from MiniStack

| Resource | AWS | Details |
|----------|-----|---------|
| AWS API | Real AWS account | Region: ap-southeast-1 |
| EKS | AWS EKS 1.29 | m5.large, 2-5 nodes, managed node group |
| RDS | AWS RDS PostgreSQL 15 | Multi-AZ, deletion protection, perf insights |
| Vault | HA mode (Raft storage) | 3 replicas, KMS auto-unseal, SSM token storage |
| Linkerd certs | Vault PKI (external CA) | `external_ca=true`, issuer from Vault |
| GitHub Runner | ARC (Actions Runner Controller) | Self-hosted ephemeral runners on EKS |
| State backend | Real S3 + DynamoDB | Persistent, shared state |
| ArgoCD | LoadBalancer | AWS ALB / NLB for external access |

### Network Topology

```text
┌─── AWS (ap-southeast-1) ──────────────────────────────────────────────┐
│                                                                        │
│  ┌─── VPC (10.0.0.0/16) ──────────────────────────────────────────┐  │
│  │                                                                  │  │
│  │  ┌─ Public Subnets ──────────────────────────────────────────┐  │  │
│  │  │  NAT Gateway                                               │  │  │
│  │  │  ALB Ingress Controller                                    │  │  │
│  │  └────────────────────────────────────────────────────────────┘  │  │
│  │                          │                                       │  │
│  │  ┌─ Private Subnets ────┴───────────────────────────────────┐   │  │
│  │  │                                                           │   │  │
│  │  │  EKS Cluster (v1.29)                                      │   │  │
│  │  │  ┌─ Node Group (m5.large x2-5) ───────────────────────┐  │   │  │
│  │  │  │                                                      │  │   │  │
│  │  │  │  Namespaces:                                         │  │   │  │
│  │  │  │  ┌─ vault ─────────────────────────────────────┐    │  │   │  │
│  │  │  │  │  vault-0, vault-1, vault-2  (HA Raft)       │    │  │   │  │
│  │  │  │  │  vault-secrets-operator                      │    │  │   │  │
│  │  │  │  │  Auto-unseal via KMS                         │    │  │   │  │
│  │  │  │  │  Root token stored in SSM Parameter Store    │    │  │   │  │
│  │  │  │  └──────────────────────────────────────────────┘    │  │   │  │
│  │  │  │  ┌─ argocd ────────────────────────────────────┐    │  │   │  │
│  │  │  │  │  server (LoadBalancer → ALB)                 │    │  │   │  │
│  │  │  │  └──────────────────────────────────────────────┘    │  │   │  │
│  │  │  │  ┌─ linkerd ───────────────────────────────────┐    │  │   │  │
│  │  │  │  │  External CA (certs from Vault PKI)          │    │  │   │  │
│  │  │  │  │  identity, destination, proxy-injector        │    │  │   │  │
│  │  │  │  └──────────────────────────────────────────────┘    │  │   │  │
│  │  │  │  ┌─ consul ────────────────────────────────────┐    │  │   │  │
│  │  │  │  │  Service mesh (deployed by ArgoCD wave 1)    │    │  │   │  │
│  │  │  │  └──────────────────────────────────────────────┘    │  │   │  │
│  │  │  │  ┌─ arc-runners ───────────────────────────────┐    │  │   │  │
│  │  │  │  │  GitHub Actions Runner Controller            │    │  │   │  │
│  │  │  │  │  Ephemeral runners (scale 0 → N on demand)   │    │  │   │  │
│  │  │  │  └──────────────────────────────────────────────┘    │  │   │  │
│  │  │  │  ┌─ payments-app ──────────────────────────────┐    │  │   │  │
│  │  │  │  │  App pods (deployed by ArgoCD wave 4)        │    │  │   │  │
│  │  │  │  │  Linkerd mesh injected                       │    │  │   │  │
│  │  │  │  │  Vault sidecar for DB creds                  │    │  │   │  │
│  │  │  │  └──────────────────────────────────────────────┘    │  │   │  │
│  │  │  │  ┌─ monitoring ────────────────────────────────┐    │  │   │  │
│  │  │  │  │  datadog (wave 2), flagger (wave 3)          │    │  │   │  │
│  │  │  │  └──────────────────────────────────────────────┘    │  │   │  │
│  │  │  └──────────────────────────────────────────────────────┘  │   │  │
│  │  └────────────────────────────────────────────────────────────┘   │  │
│  │                                                                   │  │
│  │  ┌─ Database Subnets ────────────────────────────────────────┐   │  │
│  │  │  RDS PostgreSQL 15 (Multi-AZ)                              │   │  │
│  │  │  DB: payments                                              │   │  │
│  │  │  Vault DB secrets engine connects directly                 │   │  │
│  │  └────────────────────────────────────────────────────────────┘   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│  ┌─ KMS ─────────────────┐  ┌─ SSM Parameter Store ─────────────┐     │
│  │  Vault auto-unseal key │  │  /vault/root-token                 │     │
│  └────────────────────────┘  └────────────────────────────────────┘     │
│                                                                         │
│  ┌─ S3 ──────────────────┐  ┌─ DynamoDB ─────────────────────────┐    │
│  │  tf-state-terragrunt-  │  │  tf-state-lock                     │    │
│  │  infra-ap-southeast-1  │  │  (state locking)                   │    │
│  └────────────────────────┘  └────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

### Vault Provider Connectivity

```text
  Terraform (your machine)
       │
       │  before_hook: kubectl port-forward svc/vault 18200:8200 -n vault
       │
       ▼
  localhost:18200 ──► kubectl tunnel ──► vault.vault.svc:8200
       │
       │  Vault provider uses http://localhost:18200
       │  Token from SSM Parameter Store (aws) or "root" (ministack)
       │
       ▼
  Vault creates resources:
    ├─ K8s auth backend
    ├─ Transit key (payments-app)
    ├─ Database secrets (→ RDS)
    ├─ KV v2 static creds
    └─ PKI CAs (certs unit)
```

---

## Vault Secrets Flow

```text
┌─────────────────────────────────────────────────────────────────────┐
│                          Vault Server                                │
│                                                                      │
│  ┌─ Auth ────────────────────────────────────────────────────────┐  │
│  │                                                                │  │
│  │  Kubernetes Auth (path: kubernetes)                            │  │
│  │  ├─ Bound to EKS cluster CA + API host                        │  │
│  │  └─ Role: payments-app                                         │  │
│  │       ├─ bound_sa: payments-app                                │  │
│  │       ├─ bound_ns: payments-app                                │  │
│  │       └─ policies: payments-app-policy                         │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─ Secrets Engines ─────────────────────────────────────────────┐  │
│  │                                                                │  │
│  │  Transit (path: transit)                                       │  │
│  │  └─ Key: payments-app (aes256-gcm96)                           │  │
│  │     └─ App encrypts/decrypts payment data via Vault API        │  │
│  │                                                                │  │
│  │  Database (path: payments-app/database)                        │  │
│  │  └─ Connection: payments (PostgreSQL)                          │  │
│  │     ├─ MiniStack: host.docker.internal:15432/payments          │  │
│  │     └─ AWS:       <rds-endpoint>:5432/payments                 │  │
│  │     └─ Role: payments                                          │  │
│  │        ├─ Dynamic username/password                            │  │
│  │        ├─ TTL: 3600s (1h)                                      │  │
│  │        ├─ Max TTL: 86400s (24h)                                │  │
│  │        └─ CREATE ROLE + GRANT SELECT,INSERT,UPDATE,DELETE      │  │
│  │                                                                │  │
│  │  KV v2 (path: payments-processor/static)                       │  │
│  │  └─ Secret: creds                                              │  │
│  │     ├─ username                                                │  │
│  │     ├─ password                                                │  │
│  │     └─ vault_addr                                              │  │
│  │                                                                │  │
│  │  PKI — certs unit (3 backends)                                 │  │
│  │  ├─ consul/server/pki  ── Consul server TLS                    │  │
│  │  ├─ consul/connect/pki ── Consul Connect mTLS                  │  │
│  │  └─ consul/api-gw/pki ── Consul API Gateway TLS               │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─ Policy: payments-app-policy ─────────────────────────────────┐  │
│  │  transit/encrypt/payments-app    ── encrypt                    │  │
│  │  transit/decrypt/payments-app    ── decrypt                    │  │
│  │  payments-app/database/creds/*   ── read (dynamic DB creds)    │  │
│  │  payments-processor/static/*     ── read (static creds)        │  │
│  └────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘

  App Pod Flow:
  ─────────────
  1. Pod starts with ServiceAccount: payments-app
  2. Vault sidecar/CSI authenticates via K8s auth
  3. Gets dynamic DB creds (auto-renewed every 1h)
  4. Reads static creds from KV v2
  5. Calls Transit API for encrypt/decrypt
```
