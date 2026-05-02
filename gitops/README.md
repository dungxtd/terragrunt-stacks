# GitOps — payments-app platform

ArgoCD-managed runtime layer. Terraform handles infra (EKS, RDS, Vault, ArgoCD itself); everything below is delivered by ArgoCD pulling this directory.

## Layout

```
gitops/
├── apps/                              ← ArgoCD Application + ApplicationSet manifests
│   ├── root.yaml                      ← App-of-Apps; watches gitops/apps/ recursively
│   ├── appset-platform.yaml           ← upstream Helm charts (consul, datadog, flagger)
│   ├── payments-app.yaml              ← in-house chart (gitops/charts/payments-app)
│   └── platform-ui.yaml               ← raw Ingress manifests (gitops/platform-ui/)
├── charts/                            ← in-house Helm charts
│   ├── _lib/                          ← library chart: lib.workload, lib.mesh, lib.vault
│   └── payments-app/                  ← single services.yaml loops Values.services
├── values/                            ← per-app, per-env Helm values
│   ├── consul/production.yaml
│   ├── datadog/production.yaml
│   ├── flagger/production.yaml
│   └── payments-app/production.yaml
└── platform-ui/                       ← raw kubectl ingress manifests (host-routed ALBs)
    └── ingresses.yaml
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
| 1 | consul | upstream `hashicorp/consul` |
| 2 | datadog | upstream `datadog/datadog` |
| 3 | flagger | upstream `flagger/flagger` |
| 4 | payments-app | local `gitops/charts/payments-app` |
| 5 | platform-ui | raw manifests `gitops/platform-ui/` |

## Values

Multi-source pattern — each Application has two sources:

1. The Helm chart (upstream OR `gitops/charts/<name>`)
2. This repo as a `ref: values` source, supplying `valueFiles: [$values/gitops/values/<app>/<env>.yaml]`

Add a new env: drop `gitops/values/<app>/<env>.yaml` and reference it in the matching `apps/*.yaml`.

## payments-app Chart

Single source of truth: `gitops/values/payments-app/production.yaml` — contains a `services:` map. `templates/services.yaml` loops the map and includes `lib.workload` for each entry. To add a microservice: add an entry to `services:`. No template changes.

Specials kept as standalone templates: `canary.yaml`, `secrets.yaml` (Vault/SOPS), `ingress.yaml`, `service-mesh.yaml`, `serviceaccount.yaml`, `namespace.yaml`, `*-configmap.yaml`, `payments-app-database-service.yaml` (ExternalName for RDS).

## Ingresses (ALBs)

Shared ALB (`alb.ingress.kubernetes.io/group.name: platform`):
- `argocd-ui` → `/argocd` → argocd-server
- `payments-app` → `/` → frontend

Dedicated ALBs (subpath broken — UIs hardcode asset paths):
- `consul-ui`, `vault-ui`, `linkerd-viz`

## Known Runtime Gaps

- Datadog `403 API Key invalid` — needs real `DD_API_KEY` in `Secret/datadog-cluster-agent` (recommend ExternalSecrets pulling from Vault)
- Flagger canary stuck `Initializing` — needs `linkerd-smi` extension (Linkerd ≥2.14 dropped SMI by default)
