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

if [ "$ENV" = "ministack" ]; then
  export KUBECONFIG="$REPO_ROOT/.kubeconfig-ministack"
  export VAULT_ADDR="http://localhost:18200"
  export VAULT_TOKEN="root"
  export AWS_REGION="ap-southeast-1"
  export EKS_CLUSTER_NAME="terragrunt-infra-eks"
  export ARGOCD_SERVER="https://localhost:30443"
else
  # Override stale AWS_PROFILE values that may have been set previously
  # (e.g. older versions of this script set it to "terragrunt" — non-existent
  # profile in most setups). Force "default" unless caller pre-set something
  # else AND that profile actually exists.
  if [ -n "${AWS_PROFILE:-}" ] && ! aws configure list-profiles 2>/dev/null | grep -qx "$AWS_PROFILE"; then
    echo "  warn: AWS_PROFILE=$AWS_PROFILE not found, falling back to 'default'" >&2
    unset AWS_PROFILE
  fi
  : "${AWS_PROFILE:=default}"
  export AWS_PROFILE
  export AWS_REGION="ap-southeast-1"
  export EKS_CLUSTER_NAME="terragrunt-infra-eks"
  export KUBECONFIG="$HOME/.kube/config"

  # Vault token: read directly from SSM (where scripts/vault-init.sh wrote it).
  # Reading via `terragrunt output` returns stale placeholder captured in
  # state before the init script overwrote SSM.
  export VAULT_TOKEN=$(aws ssm get-parameter \
    --name /terragrunt-infra/vault/root-token \
    --with-decryption \
    --query Parameter.Value \
    --output text 2>/dev/null || echo "")

  # Vault is in-cluster only — use port-forward (make pf-vault) and address localhost.
  export VAULT_ADDR="http://localhost:18200"

  ARGOCD_HOSTNAME=$(kubectl get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [ -n "$ARGOCD_HOSTNAME" ]; then
    export ARGOCD_SERVER="https://$ARGOCD_HOSTNAME"
  else
    export ARGOCD_SERVER="https://localhost:8080"  # via make pf-argocd
  fi
fi

export ARGOCD_ADMIN_PASS=$(KUBECONFIG="${KUBECONFIG:-}" kubectl get secrets -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")

# Trim VAULT_TOKEN preview for display (security)
TOKEN_PREVIEW=""
[ -n "$VAULT_TOKEN" ] && TOKEN_PREVIEW="${VAULT_TOKEN:0:8}…(${#VAULT_TOKEN} chars)"

echo "Environment ($ENV):"
echo "  AWS_PROFILE=${AWS_PROFILE:-(unset)}"
echo "  AWS_REGION=$AWS_REGION"
echo "  KUBECONFIG=$KUBECONFIG"
echo "  EKS_CLUSTER_NAME=$EKS_CLUSTER_NAME"
echo "  VAULT_ADDR=$VAULT_ADDR  (run 'make pf-vault' to forward)"
echo "  VAULT_TOKEN=$TOKEN_PREVIEW"
echo "  ARGOCD_SERVER=$ARGOCD_SERVER  (run 'make pf-argocd' if localhost)"
echo "  ARGOCD_ADMIN_PASS=$ARGOCD_ADMIN_PASS  (user: admin)"
