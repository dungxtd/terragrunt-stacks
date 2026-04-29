#!/usr/bin/env bash
# Set environment variables for the active environment.
# Works with both MiniStack (local) and AWS (production).
# Usage: source load_env.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
STACK_DIR="$SCRIPT_DIR/stacks/vault-consul/.terragrunt-stack"

# Detect active environment
ACTIVE_ENV=$(grep 'active_env' "$SCRIPT_DIR/local.hcl" | sed 's/.*"\(.*\)".*/\1/')

tg_output() {
  local unit="$1" key="$2"
  cd "$STACK_DIR/$unit" && terragrunt output -raw "$key" 2>/dev/null || echo ""
}

if [ "$ACTIVE_ENV" = "ministack" ]; then
  export KUBECONFIG="$SCRIPT_DIR/.kubeconfig-ministack"
  export VAULT_ADDR="http://localhost:18200"
  export VAULT_TOKEN="root"
  export AWS_REGION="ap-southeast-1"
  export EKS_CLUSTER_NAME="terragrunt-infra-eks"
  export ARGOCD_SERVER="https://localhost:30443"
else
  export VAULT_ADDR=$(tg_output vault vault_address)
  export VAULT_TOKEN=$(tg_output vault vault_root_token)
  export AWS_REGION=$(tg_output vpc region)
  export EKS_CLUSTER_NAME=$(tg_output eks cluster_name)
  export ARGOCD_SERVER="https://$(kubectl get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "localhost")"
fi

export ARGOCD_ADMIN_PASS=$(KUBECONFIG="${KUBECONFIG:-}" kubectl get secrets -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")

echo "Environment ($ACTIVE_ENV):"
echo "  KUBECONFIG=$KUBECONFIG"
echo "  VAULT_ADDR=$VAULT_ADDR  (requires: kubectl port-forward svc/vault 18200:8200 -n vault)"
echo "  VAULT_TOKEN=$VAULT_TOKEN"
echo "  ARGOCD_SERVER=$ARGOCD_SERVER"
echo "  ARGOCD_ADMIN_PASS=$ARGOCD_ADMIN_PASS  (user: admin)"
echo "  AWS_REGION=$AWS_REGION"
echo "  EKS_CLUSTER_NAME=$EKS_CLUSTER_NAME"
