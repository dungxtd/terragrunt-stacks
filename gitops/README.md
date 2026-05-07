# GitOps — payments-app platform

ArgoCD-managed runtime layer. Terraform handles infra (EKS, RDS, Vault, ArgoCD itself, ALB); everything below is delivered by ArgoCD pulling this directory.

## Layout

```
gitops/
├── apps/                              ← ArgoCD Application + ApplicationSet manifests
│   ├── root.yaml                      ← App-of-Apps; watches gitops/apps/ recursively
│   ├── projects.yaml                  ← AppProject `platform` (allowed namespaces, sourceRepos)
│   ├── gateway-api-crds.yaml          ← Gateway API CRDs
│   ├── appset-platform.yaml           ← upstream Helm charts (kube-prometheus-stack, flagger, loadtester)
│   ├── external-secrets.yaml          ← external-secrets-operator
│   ├── secret-stores.yaml             ← in-house chart wiring SecretStores → Vault
│   ├── linkerd-viz-policy.yaml        ← Linkerd-viz authz policy
│   ├── payments-app.yaml              ← in-house chart (gitops/charts/payments-app)
│   └── jaeger-demo.yaml               ← raw manifests (Jaeger + HotROD demo)
├── charts/                            ← in-house Helm charts
│   ├── _lib/                          ← library chart: lib.workload, lib.mesh, lib.vault
│   ├── payments-app/                  ← single Spring Boot service using Vault → RDS
│   └── secret-stores/                 ← SecretStore wiring chart
├── values/                            ← per-app, per-env Helm values
│   ├── kube-prometheus-stack/production.yaml
│   ├── flagger/production.yaml
│   ├── loadtester/production.yaml
│   ├── external-secrets/production.yaml
│   ├── secret-stores/production.yaml
│   └── payments-app/production.yaml
└── platform/                          ← raw kubectl manifests
    ├── linkerd-viz-policy/            ← Linkerd-viz authz policy
    └── jaeger-demo/                   ← Jaeger all-in-one + HotROD deployments
```

## Bootstrap

CI (`.github/workflows/gitops.yml`) does only one thing on push to `main`:

```bash
kubectl apply -f gitops/apps/root.yaml
```

The `root` Application then reconciles `gitops/apps/` recursively, creating each child Application. Adding a new app = drop a file in `gitops/apps/` and push. ArgoCD picks it up.

## Sync Waves

Set via `argocd.argoproj.io/sync-wave` annotation in each app file:

| Wave | App | Source |
|------|-----|--------|
| 0 | external-secrets | upstream `external-secrets/external-secrets` |
| 1 | secret-stores | local `gitops/charts/secret-stores` |
| 2 | kube-prometheus-stack | upstream `prometheus-community/kube-prometheus-stack` |
| 3 | flagger / loadtester | upstream `flagger/flagger` |
| 4 | payments-app | local `gitops/charts/payments-app` |
| 5 | jaeger-demo | raw manifests `gitops/platform/jaeger-demo/` |

## Values

Multi-source pattern — each Application has two sources:

1. The Helm chart (upstream OR `gitops/charts/<name>`)
2. This repo as a `ref: values` source, supplying `valueFiles: [$values/gitops/values/<app>/<env>.yaml]`

Add a new env: drop `gitops/values/<app>/<env>.yaml` and reference it in the matching `apps/*.yaml`.

## payments-app Chart

Single Spring Boot service that uses **Vault dynamic credentials → RDS**. No frontend, no API gateway — pure backend showcase.

Files:
- `templates/services.yaml` — loops `Values.services` (currently one entry)
- `templates/secrets.yaml` — VaultConnection + VaultAuth (vault-secrets-operator)
- `templates/payments-app-database-service.yaml` — ExternalName service → RDS endpoint
- `templates/serviceaccount.yaml` — `payments-app` SA bound to Vault role

To add a service: add entry to `services:` in values. No template changes.

## ALB

The single public ALB is **TF-managed** in `units/alb/`. K8s `TargetGroupBinding` (also TF) registers `payments-app` pods to the AWS Target Group. Other UIs (ArgoCD, Vault, Linkerd-viz, Jaeger, HotROD, Grafana, Prometheus) accessed via `make pf-all` port-forwards.

## Observability stack (replacement for Datadog)

| Tool | Use |
|------|-----|
| **kube-prometheus-stack** | cluster + pod metrics, Grafana dashboards |
| **Linkerd-viz Prometheus** | mesh-level golden metrics |
| **Jaeger + HotROD** | distributed tracing demo |
