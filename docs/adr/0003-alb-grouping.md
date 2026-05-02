# ADR 0003: ALB grouping for shared cost

Date: 2026-05-01
Status: Accepted (partial)

## Context

5 ingresses → 5 separate AWS ALBs without grouping → 5 × $16/mo = ~$80/mo.

## Decision

Group ingresses where possible via `alb.ingress.kubernetes.io/group.name: platform`:

| Ingress | Group | Reason |
|---------|-------|--------|
| `argocd-ui` | `platform` | path `/argocd` |
| `payments-app` | `platform` | path `/` (catch-all, group.order: 99) |
| `consul-ui` | dedicated | UI hardcodes `/v1/` API path → subpath broken |
| `vault-ui` | dedicated | Vault has no UI subpath support |
| `linkerd-viz` | dedicated | viz hardcodes asset paths |

## Consequences

- ✅ Saves 1 ALB (~$16/mo) — 4 left = $64/mo (was $80)
- 🔴 Consul/Vault/linkerd-viz still need own ALBs until upstream fixes subpath routing
- 🟡 Future: replace ALB ingresses with a single AWS Gateway API + HTTPRoute per service (one LB total) once gateway-api-controller-eks-aws supports all required protocols
