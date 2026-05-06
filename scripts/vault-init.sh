#!/usr/bin/env bash
# Initialize Vault and write root token + recovery keys to SSM.
# Idempotent: skips if Vault already initialized.
#
# Required env:
#   VAULT_MODE       — "ha" or "dev"
#   AWS_REGION       — AWS region for SSM
#   KUBECONFIG       — path to kubeconfig
# Optional env:
#   SSM_ENDPOINT     — custom SSM endpoint (LocalStack)
#   DEV_ROOT_TOKEN   — root token to store in dev mode (default "root")
#   SSM_TOKEN_NAME   — SSM param path for root token
#                      (default /terragrunt-infra/vault/root-token)
#   SSM_KEY_PREFIX   — SSM param prefix for recovery keys
#                      (default /terragrunt-infra/vault/recovery-key-)

set -euo pipefail

VAULT_MODE="${VAULT_MODE:?VAULT_MODE required (ha|dev)}"
AWS_REGION="${AWS_REGION:?AWS_REGION required}"
KUBECONFIG="${KUBECONFIG:?KUBECONFIG required}"
SSM_ENDPOINT="${SSM_ENDPOINT:-}"
DEV_ROOT_TOKEN="${DEV_ROOT_TOKEN:-root}"
SSM_TOKEN_NAME="${SSM_TOKEN_NAME:-/terragrunt-infra/vault/root-token}"
SSM_KEY_PREFIX="${SSM_KEY_PREFIX:-/terragrunt-infra/vault/recovery-key-}"

export KUBECONFIG AWS_DEFAULT_REGION="$AWS_REGION"

SSM_ENDPOINT_ARG=""
SSM_ENV_PREFIX=""
if [ -n "$SSM_ENDPOINT" ]; then
  SSM_ENDPOINT_ARG="--endpoint-url $SSM_ENDPOINT"
  SSM_ENV_PREFIX="AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test"
fi

put_ssm() {
  local name="$1" value="$2"
  # shellcheck disable=SC2086
  env $SSM_ENV_PREFIX aws ssm put-parameter \
    --name "$name" \
    --value "$value" \
    --type SecureString \
    --overwrite \
    $SSM_ENDPOINT_ARG \
    >/dev/null
}

if [ "$VAULT_MODE" = "dev" ]; then
  echo "==> Vault dev mode: waiting for pod ready"
  kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=vault \
    -n vault --timeout=300s

  echo "==> Storing dev root token in SSM"
  put_ssm "$SSM_TOKEN_NAME" "$DEV_ROOT_TOKEN"
  echo "✓ done"
  exit 0
fi

if [ "$VAULT_MODE" != "ha" ]; then
  echo "ERROR: unknown VAULT_MODE=$VAULT_MODE" >&2
  exit 1
fi

echo "==> Vault HA mode: wait vault-0 Running"
for i in $(seq 1 30); do
  PHASE=$(kubectl get pod vault-0 -n vault -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  [ "$PHASE" = "Running" ] && { echo "vault-0 Running"; break; }
  echo "  phase=${PHASE:-pending} attempt $i/30, retry in 10s"
  sleep 10
done

echo "==> Wait Vault API responsive"
STATUS=""
for i in $(seq 1 30); do
  STATUS=$(kubectl exec vault-0 -n vault -- \
    env VAULT_ADDR=http://127.0.0.1:8200 \
    vault status -format=json 2>/dev/null || true)
  [ -n "$STATUS" ] && { echo "API ready"; break; }
  echo "  attempt $i/30, retry in 10s"
  sleep 10
done

INITIALIZED=$(echo "$STATUS" | python3 -c \
  "import sys,json; print(json.load(sys.stdin)['initialized'])" 2>/dev/null || echo "False")

if [ "$INITIALIZED" = "True" ]; then
  echo "✓ Vault already initialized, skip"
  exit 0
fi

echo "==> Initializing Vault"
INIT=$(kubectl exec vault-0 -n vault -- \
  env VAULT_ADDR=http://127.0.0.1:8200 \
  vault operator init \
    -recovery-shares=5 \
    -recovery-threshold=3 \
    -format=json)

ROOT_TOKEN=$(echo "$INIT" | python3 -c \
  "import sys,json; print(json.load(sys.stdin)['root_token'])")

echo "==> Writing root token to SSM ($SSM_TOKEN_NAME)"
put_ssm "$SSM_TOKEN_NAME" "$ROOT_TOKEN"

for i in 0 1 2 3 4; do
  KEY=$(echo "$INIT" | python3 -c \
    "import sys,json; print(json.load(sys.stdin)['recovery_keys_b64'][$i])")
  echo "==> Writing recovery key $i to SSM"
  put_ssm "${SSM_KEY_PREFIX}${i}" "$KEY"
done

echo "✓ Vault initialized, secrets stored in SSM"
