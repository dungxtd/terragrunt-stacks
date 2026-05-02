# Runbook: Flagger canary stuck `Initializing`

## Symptom

```
$ kubectl get canary -A
NAMESPACE      NAME           STATUS         WEIGHT   LASTTRANSITIONTIME
payments-app   payments-app   Initializing   0        2026-...
```

Flagger logs:
```
prometheus not avaiable: running query failed: error response: Status 403 Forbidden
TrafficSplit ... smi-spec.io: not found
```

## Root Cause

Flagger linkerd provider expects:
1. Prometheus reachable at `metricsServer` URL
2. SMI `TrafficSplit` CRD installed in cluster

Linkerd ≥2.14 ships *without* SMI by default. Linkerd-viz Prometheus has `ServerAuthorization` blocking unauthorized scrape.

## Fix

### Install linkerd-smi extension
```bash
linkerd smi install | kubectl apply -f -
```

### Allow flagger to scrape linkerd-viz Prometheus
Create `MeshTLSAuthentication` + `AuthorizationPolicy` granting `flagger-system` SA access to `prometheus` Server in `linkerd-viz` namespace. See linkerd-viz docs.

### Restart flagger
```bash
kubectl rollout restart deployment/flagger -n flagger-system
```

Canary advances `Initializing → Initialized → Promoting → Succeeded`.

## Verify

```bash
kubectl logs -n flagger-system deploy/flagger | grep -i payments-app
kubectl get canary -A -w
```
