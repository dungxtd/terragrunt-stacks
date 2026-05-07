# ADR 0001: Linkerd over Consul Connect

Date: 2026-05-01
Status: Accepted

## Context

Cluster originally ran both Consul Connect and Linkerd. Each injector inserted a sidecar into every pod → doubled resource use, conflicting traffic routing, datadog cluster-agent crashlooped (`multiple Consul services registered`).

## Decision

Keep Linkerd as service mesh. Consul fully removed (2026-05-06): GitOps app deleted, `units/certs` (Consul PKI backends) deleted, all Consul values/charts purged.

## Consequences

- ✅ Single sidecar per pod
- ✅ Flagger canary aligns with `provider: linkerd`
- ✅ Consul removed — no stale catalog entries, no dual-sidecar risk
