#!/usr/bin/env bash
# Production environment — reads from terragrunt outputs
# Usage: source set_env.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Vault (vault-consul env only)
export VAULT_ADDR=$(cd "$SCRIPT_DIR/units/vault" && terragrunt output -raw vault_address 2>/dev/null || echo "")
export VAULT_TOKEN=$(cd "$SCRIPT_DIR/units/vault" && terragrunt output -raw vault_root_token 2>/dev/null || echo "")

# Consul (vault-consul env only)
export CONSUL_HTTP_ADDR=$(cd "$SCRIPT_DIR/units/consul" && terragrunt output -raw consul_address 2>/dev/null || echo "")
export CONSUL_HTTP_TOKEN=$(cd "$SCRIPT_DIR/units/consul" && terragrunt output -raw consul_token 2>/dev/null || echo "")

# ArgoCD
export ARGOCD_SERVER="https://$(kubectl get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "localhost")"
export ARGOCD_AUTH_TOKEN=$(kubectl get secrets -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")

# EKS
export AWS_REGION=$(cd "$SCRIPT_DIR/units/vpc" && terragrunt output -raw region 2>/dev/null || echo "ap-southeast-1")
export EKS_CLUSTER_NAME=$(cd "$SCRIPT_DIR/units/eks" && terragrunt output -raw cluster_name 2>/dev/null || echo "")

echo "Environment variables set:"
echo "  VAULT_ADDR=$VAULT_ADDR"
echo "  CONSUL_HTTP_ADDR=$CONSUL_HTTP_ADDR"
echo "  ARGOCD_SERVER=$ARGOCD_SERVER"
echo "  AWS_REGION=$AWS_REGION"
echo "  EKS_CLUSTER_NAME=$EKS_CLUSTER_NAME"
