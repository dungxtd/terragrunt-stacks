#!/usr/bin/env bash
# Drain residual k8s resources not owned by ArgoCD or Terragrunt.
# Skips Terragrunt-managed namespaces (vault, argocd, linkerd*,
# kube-system, vault-secrets-operator-system) — their helm_release destroy
# handles StatefulSets and PVCs. Killing vault SS here breaks vault-config
# destroy (no Vault API to call).
set -euo pipefail

if ! kubectl get ns >/dev/null 2>&1; then
  echo "cluster unreachable — skip"
  exit 0
fi

# TargetGroupBindings: drain BEFORE aws-alb controller dies so the finalizer
# deregisters targets cleanly. alb unit's kubernetes_manifest destroy then
# becomes a no-op (CR already gone → 404 tolerated).
kubectl delete targetgroupbindings.elbv2.k8s.aws -A --all --timeout=120s --ignore-not-found || true

PROTECTED="vault|vault-secrets-operator-system|argocd|linkerd|linkerd-viz|kube-system|kube-public|kube-node-lease|default"
APP_NS=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}' \
  | tr ' ' '\n' | grep -Ev "^(${PROTECTED})$" || true)

for ns in $APP_NS; do
  kubectl -n "$ns" delete ingress --all --timeout=120s --ignore-not-found || true
  kubectl get svc -n "$ns" -o json 2>/dev/null \
    | jq -r '.items[] | select(.spec.type=="LoadBalancer") | .metadata.name' \
    | while read -r svc; do kubectl -n "$ns" delete svc "$svc" --timeout=120s || true; done
  kubectl -n "$ns" delete pvc --all --timeout=120s --ignore-not-found || true
done
