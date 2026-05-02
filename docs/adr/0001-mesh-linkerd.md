# ADR 0001: Linkerd over Consul Connect

Date: 2026-05-01
Status: Accepted

## Context

Cluster originally ran both Consul Connect and Linkerd. Each injector inserted a sidecar into every pod → doubled resource use, conflicting traffic routing, datadog cluster-agent crashlooped (`multiple Consul services registered`).

## Decision

Keep Linkerd as service mesh. Disable Consul Connect inject (`connectInject.enabled: false` in `gitops/values/consul/production.yaml`). Consul stays as service catalog + KV only.

## Consequences

- ✅ Single sidecar per pod
- ✅ Flagger canary aligns with `provider: linkerd`
- ⚠️ Flagger needs `linkerd-smi` extension (Linkerd ≥2.14 dropped SMI by default) — TODO
- ⚠️ Old Consul registrations from crashlooped pods left as stale catalog entries; cleanup runbook: [consul-stale-services.md](../runbooks/consul-stale-services.md)
