# Runbook: Consul UI shows stale services with `critical` health

## Symptom

Consul UI lists services that no longer have running pods (e.g. `datadog-cluster-agent-86bbfc87d-wzd2r-...`). Health = `critical`. Pods deleted long ago.

## Root Cause

`consul-k8s-endpoints-controller` deregisters services on pod termination. If `connectInject.enabled: false` was set *while* such pods existed, the controller stopped before pruning. Stale registrations sit in Consul raft state forever.

## Fix

```bash
TOKEN=$(kubectl get secret -n consul consul-bootstrap-acl-token -o jsonpath='{.data.token}' | base64 -d)

cat > /tmp/dr.sh <<'SCRIPT'
#!/bin/sh
T="$1"
SVCS="$2"
for svc in $SVCS; do
  curl -sk --cacert /consul/tls/ca/tls.crt -H "X-Consul-Token: $T" \
    "https://localhost:8501/v1/catalog/service/$svc" \
    | sed 's/},{/}\n{/g' | while read line; do
      NODE=$(echo "$line" | sed -nE 's/.*"Node":"([^"]+)".*/\1/p')
      SID=$(echo  "$line" | sed -nE 's/.*"ServiceID":"([^"]+)".*/\1/p')
      [ -z "$NODE" ] || [ -z "$SID" ] && continue
      curl -sk --cacert /consul/tls/ca/tls.crt -H "X-Consul-Token: $T" \
        -X PUT -d "{\"Node\":\"$NODE\",\"ServiceID\":\"$SID\"}" \
        https://localhost:8501/v1/catalog/deregister
    done
done
SCRIPT

kubectl cp /tmp/dr.sh consul/consul-server-0:/tmp/dr.sh -c consul
kubectl exec -n consul consul-server-0 -c consul -- sh /tmp/dr.sh "$TOKEN" \
  "datadog-cluster-agent datadog-cluster-agent-sidecar-proxy ..."
```

Pass each stale service name as args. Loop may need to run twice (single-instance services have JSON without `},{` to split).

## Verify

```bash
kubectl exec -n consul consul-server-0 -c consul -- consul catalog services
```

Should list only live services.

## Prevention

Always disable `connectInject` BEFORE deleting stale workloads, OR re-enable injector briefly to let it prune, then disable.
