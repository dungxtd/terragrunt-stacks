#!/usr/bin/env bash
# Cascade-delete all ArgoCD ApplicationSets and Applications.
# resources-finalizer triggers argocd-application-controller to delete managed
# k8s resources (Ingress, PVC, Service LB) in reverse sync-wave order so AWS
# controllers reconcile ALB / EBS / NLB cleanup before VPC is destroyed.
set -euo pipefail

if ! kubectl get ns argocd >/dev/null 2>&1; then
  echo "argocd namespace gone — skip"
  exit 0
fi

# Stop ApplicationSet controller — prevents app re-creation during teardown
kubectl -n argocd scale deploy/argocd-applicationset-controller --replicas=0 || true

# Delete ApplicationSets first (no finalizers, frees template-owned apps)
kubectl -n argocd delete applicationsets.argoproj.io --all --timeout=120s || true

# Delete root app — resources-finalizer cascades children in reverse wave order
kubectl -n argocd delete application root --cascade=foreground --timeout=600s || true

# Catch any leftover apps not owned by root (linkerd-viz-policy, jaeger-demo, etc.)
kubectl -n argocd delete applications.argoproj.io --all --cascade=foreground --timeout=600s || true

# Strip stuck finalizers as last resort (controller dead / never reconciled)
for app in $(kubectl -n argocd get applications.argoproj.io -o name 2>/dev/null); do
  kubectl -n argocd patch "$app" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
done
kubectl -n argocd delete applications.argoproj.io --all --timeout=60s || true
