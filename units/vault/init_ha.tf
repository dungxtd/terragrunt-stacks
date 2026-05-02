# HA mode (production): Vault pods start sealed/uninitialized — readiness probe
# fails until operator init runs. Poll Running phase, then use kubectl exec to
# call Vault's API on 127.0.0.1:8200 inside vault-0 (no port-forward needed).

resource "terraform_data" "vault_init_ha" {
  count = var.vault_mode == "ha" ? 1 : 0

  depends_on = [helm_release.vault, helm_release.vault_secrets_operator]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
    command = <<-EOF
      set -euo pipefail

      echo "Waiting for vault-0 to be Running..."
      for i in $(seq 1 30); do
        PHASE=$(kubectl get pod vault-0 -n vault -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        [ "$PHASE" = "Running" ] && { echo "vault-0 is Running"; break; }
        echo "  phase=$${PHASE:-pending} attempt $i/30, retrying in 10s..."
        sleep 10
      done

      echo "Waiting for Vault API to respond..."
      for i in $(seq 1 30); do
        STATUS=$(kubectl exec vault-0 -n vault -- \
          curl -sf http://127.0.0.1:8200/v1/sys/init 2>/dev/null || true)
        [ -n "$STATUS" ] && { echo "Vault API ready"; break; }
        echo "  attempt $i/30, retrying in 10s..."
        sleep 10
      done

      INITIALIZED=$(echo "$STATUS" | python3 -c \
        "import sys,json; print(json.load(sys.stdin)['initialized'])" 2>/dev/null || echo "false")

      if [ "$INITIALIZED" = "True" ]; then
        echo "Vault already initialized, skipping."
        exit 0
      fi

      echo "Initializing Vault..."
      INIT=$(kubectl exec vault-0 -n vault -- \
        curl -sf -X PUT http://127.0.0.1:8200/v1/sys/init \
        -H "Content-Type: application/json" \
        -d '{"recovery_shares":5,"recovery_threshold":3}')

      ROOT_TOKEN=$(echo "$INIT" | python3 -c \
        "import sys,json; print(json.load(sys.stdin)['root_token'])")

      ${local.ssm_env_prefix} \
      aws ssm put-parameter \
        --name "${local.ssm_token_name}" \
        --value "$ROOT_TOKEN" \
        --type SecureString \
        --overwrite \
        ${local.ssm_endpoint_arg}

      for i in 0 1 2 3 4; do
        KEY=$(echo "$INIT" | python3 -c \
          "import sys,json; print(json.load(sys.stdin)['recovery_keys_b64'][$i])")
        ${local.ssm_env_prefix} \
        aws ssm put-parameter \
          --name "/terragrunt-infra/vault/recovery-key-$i" \
          --value "$KEY" \
          --type SecureString \
          --overwrite \
          ${local.ssm_endpoint_arg}
      done
      echo "Vault initialized and root token stored in SSM."
    EOF
  }

  triggers_replace = [
    helm_release.vault.metadata.app_version,
    helm_release.vault.version,
  ]
}
