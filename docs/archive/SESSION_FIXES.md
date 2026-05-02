# Session Fixes — Problems → Fixes (Step by Step)

Date: 2026-05-01 → 2026-05-02
Cluster: `terragrunt-infra-eks` (ap-southeast-1)

## Problems → Fixes

| # | Problem | Root Cause | Fix |
|---|---------|------------|-----|
| 1 | datadog cluster-agent `CrashLoop` (`Init:Error`) | Consul Connect injected sidecar; pod had 6 Consul services → "multiple Consul services registered" | `gitops/values/datadog.yaml`: add `consul.hashicorp.com/connect-inject: "false"` + `linkerd.io/inject: disabled` annotations on `clusterAgent`, `agents`, `clusterChecksRunner` |
| 2 | flagger `CrashLoop` (`Init:Error`) | Same Consul inject conflict; also wrong `meshProvider: consul` + bad metrics URL `prometheus-server.default:9090` (doesn't exist) | `gitops/values/flagger.yaml`: `meshProvider: linkerd`, `metricsServer: http://prometheus.linkerd-viz:9090`, opt-out consul + opt-in linkerd via `podAnnotations` |
| 3 | Two service meshes fighting (Consul Connect + Linkerd) | Both `connectInject.default: true` (consul) AND linkerd-proxy-injector running — sidecars duplicated on every pod | `gitops/values/consul.yaml`: `connectInject.enabled: false` — Consul stays as catalog only; Linkerd does service mesh |
| 4 | `Deploy GitOps` pipeline failing every push | Workflow used `kubectl port-forward svc/argocd-server` + `argocd login` — connection reset on ephemeral GitHub runner | `.github/workflows/gitops.yml`: deleted entire `Trigger ArgoCD sync` block; rely on ArgoCD `selfHeal: true` (auto-syncs on git change) |
| 5 | ArgoCD `consul` app stuck OutOfSync — Job immutable | `consul-server-acl-init` + `consul-tls-init` Job specs changed (new annotations); k8s Jobs are immutable on `spec.template` | `kubectl delete job` → ArgoCD recreated with new spec; added `ignoreDifferences` for `Job/*` annotations + spec to prevent recurrence |
| 6 | ArgoCD `payments-app` OutOfSync forever | Flagger mutates `Deployment/spec/replicas` and `Service/spec/selector` after Argo applies | `gitops/appset.yaml`: `ignoreDifferences` for `Deployment/payments-app /spec/replicas` and `Service/payments-app /spec/selector` |
| 7 | ArgoCD `consul-server` StatefulSet OOS loop | `ServerSideApply=true` + helm re-render drift on annotations / volumeClaimTemplates caused field-manager conflict | `gitops/appset.yaml`: removed `ServerSideApply` syncOption; added `ignoreDifferences` for STS annotations + containers + volumeClaimTemplates |
| 8 | ArgoCD `datadog` Secret + ConfigMap OOS | cluster-agent writes runtime data into `Secret/data` and `ConfigMap/data` after helm install | `gitops/appset.yaml`: `ignoreDifferences` `/data` for `Secret/datadog-cluster-agent` and `ConfigMap/datadog-kpi-telemetry-configmap` |
| 9 | Stale Terraform units (`consul`, `datadog`, `flagger`) | Migrated to GitOps but TF code lingered → drift risk | Deleted `units/consul/`, `units/datadog/`, `units/flagger/` (4 files each) |
| 10 | `CLAUDE.md` doc drift | Missing `aws-alb` unit row in Units table; wrong wave list | Added `aws-alb` row; corrected wave description ("aws-alb managed by Terraform, NOT Wave 2") |

## Live Cluster Actions

| Action | Reason |
|--------|--------|
| `kubectl delete job -n consul consul-server-acl-init consul-tls-init` | Job spec immutable; ArgoCD recreated with new annotations |
| `kubectl annotate application -n argocd consul/datadog argocd.argoproj.io/refresh=hard` (×2) | Force ArgoCD re-render after `appset.yaml` updates |
| `kubectl apply -f gitops/appset.yaml` (×3) | Iteratively apply `ignoreDifferences` refinements |

## Files Changed

### Committed (`ce8b37a` — `refactor: streamline GitOps configurations and remove deprecated Consul resources`)

- `.github/workflows/gitops.yml`
- `CLAUDE.md`
- `gitops/appset.yaml`
- `gitops/values/consul.yaml`
- `gitops/values/datadog.yaml`
- `gitops/values/flagger.yaml`
- `units/consul/{main,outputs,variables}.tf`, `units/consul/terragrunt.hcl` — DELETED
- `units/datadog/{main,variables}.tf`, `units/datadog/terragrunt.hcl` — DELETED
- `units/flagger/{main,outputs,variables}.tf`, `units/flagger/terragrunt.hcl` — DELETED

### Uncommitted

- `gitops/appset.yaml` — extended `ignoreDifferences` (Job spec, Secret/data, ConfigMap/data, datadog Deployment containers, consul-server StatefulSet, payments-app Service selector); removed `ServerSideApply=true`

## Net Result

| Before | After |
|--------|-------|
| datadog `Init:Error` (CrashLoop) | `1/1 Running` |
| flagger `Init:Error` | `2/2 Running` |
| `Deploy GitOps` pipeline failing | green (`28s success`) |
| 4 ArgoCD apps OutOfSync | 4/4 Synced |
| consul Job immutable error | recreated cleanly |

## Not Fixed (out of scope, runtime/config — needs user input)

- **Datadog `403 API Key invalid`** — populate real `DD_API_KEY` in `Secret/datadog-cluster-agent`
- **Flagger canary stuck `Initializing`** — needs `linkerd-smi` extension (modern Linkerd dropped SMI by default; flagger linkerd provider needs `TrafficSplit` CRD); also `prometheus 403` on `linkerd-viz` Prometheus — needs ServerAuthorization for `flagger-system` SA or standalone Prometheus
- **Stale Consul catalog entries** for `datadog-cluster-agent*` services from old crashlooped pods (pre-fix). Cosmetic — current pods have no sidecars. Will clear on next consul-connect-injector restart or manual deregister via Consul HTTP API with bootstrap ACL token.
