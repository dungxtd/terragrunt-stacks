#!/usr/bin/env bash
# Export environment variables for the active stack environment.
# Usage: source load_env.sh [production|ministack]
#        Defaults to production if no argument given.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV="${1:-production}"

if [[ "$ENV" != "production" && "$ENV" != "ministack" ]]; then
  echo "Usage: source scripts/load_env.sh [production|ministack]" >&2
  return 1
fi

STACK_DIR="$REPO_ROOT/stacks/vault-consul/$ENV/.terragrunt-stack"

tg_output() {
  local unit="$1" key="$2"
  cd "$STACK_DIR/$unit" && terragrunt output -raw "$key" 2>/dev/null || echo ""
}

if [ "$ENV" = "ministack" ]; then
  export KUBECONFIG="$REPO_ROOT/.kubeconfig-ministack"
  export VAULT_ADDR="http://localhost:18200"
  export VAULT_TOKEN="root"
  export AWS_REGION="ap-southeast-1"
  export EKS_CLUSTER_NAME="terragrunt-infra-eks"
  export ARGOCD_SERVER="https://localhost:30443"
else
  export AWS_PROFILE="terragrunt"
  export VAULT_ADDR=$(tg_output vault vault_address)
  export VAULT_TOKEN=$(tg_output vault vault_root_token)
  export AWS_REGION=$(tg_output vpc region)
  export EKS_CLUSTER_NAME=$(tg_output eks cluster_name)
  export KUBECONFIG="$HOME/.kube/config"
  export ARGOCD_SERVER="https://$(kubectl get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "localhost")"
fi

export ARGOCD_ADMIN_PASS=$(KUBECONFIG="${KUBECONFIG:-}" kubectl get secrets -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")

echo "Environment ($ENV):"
echo "  KUBECONFIG=$KUBECONFIG"
echo "  VAULT_ADDR=$VAULT_ADDR"
echo "  VAULT_TOKEN=$VAULT_TOKEN"
echo "  ARGOCD_SERVER=$ARGOCD_SERVER"
echo "  ARGOCD_ADMIN_PASS=$ARGOCD_ADMIN_PASS  (user: admin)"
echo "  AWS_REGION=$AWS_REGION"
echo "  EKS_CLUSTER_NAME=$EKS_CLUSTER_NAME"
