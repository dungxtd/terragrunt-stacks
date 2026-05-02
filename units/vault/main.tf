locals {
  vault_service_account_name = "vault"
}

resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  version          = "0.32.0"
  namespace        = "vault"
  create_namespace = true

  values = [var.helm_values]

  set = var.vault_mode == "ha" ? [
    {
      name  = "server.serviceAccount.create"
      value = "true"
    },
    {
      name  = "server.serviceAccount.name"
      value = local.vault_service_account_name
      type  = "string"
    },
    {
      name  = "server.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = var.vault_irsa_role_arn
      type  = "string"
    },
  ] : []
}

resource "helm_release" "vault_secrets_operator" {
  name             = "vault-secrets-operator"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault-secrets-operator"
  version          = "1.3.0"
  namespace        = "vault-secrets-operator-system"
  create_namespace = true

  depends_on = [helm_release.vault]
}

locals {
  ssm_token_name   = "/terragrunt-infra/vault/root-token"
  ssm_endpoint_arg = var.ssm_endpoint != "" ? "--endpoint-url ${var.ssm_endpoint}" : ""
  ssm_env_prefix   = var.ssm_endpoint != "" ? "AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=${var.region}" : "AWS_DEFAULT_REGION=${var.region}"
}

resource "terraform_data" "vault_init" {
  depends_on = [helm_release.vault, helm_release.vault_secrets_operator]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
    command = <<-EOF
      set -euo pipefail

      if [ "${var.vault_mode}" = "dev" ]; then
        echo "Waiting for Vault pods (dev mode)..."
        kubectl wait --for=condition=ready pod \
          -l app.kubernetes.io/name=vault \
          -n vault --timeout=300s

        # Dev mode: already unsealed, token is known
        echo "Dev mode — storing root token in SSM..."
        ${local.ssm_env_prefix} \
        aws ssm put-parameter \
          --name "${local.ssm_token_name}" \
          --value "${var.dev_root_token}" \
          --type SecureString \
          --overwrite \
          ${local.ssm_endpoint_arg}
        echo "Done."
      else
        # HA mode: pods start sealed/uninitialized — readiness probe fails until init+unseal.
        # Wait for Running phase only (not Ready), then connect and init.
        echo "Waiting for vault-0 to be Running..."
        for i in $(seq 1 30); do
          PHASE=$(kubectl get pod vault-0 -n vault -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
          [ "$PHASE" = "Running" ] && { echo "vault-0 is Running"; break; }
          echo "  phase=$PHASE attempt $i/30, retrying in 10s..."
          sleep 10
        done

        kubectl port-forward svc/vault 18200:8200 -n vault &
        PF_PID=$!
        trap "kill $PF_PID 2>/dev/null || true" EXIT
        sleep 5

        export VAULT_ADDR="http://127.0.0.1:18200"

        # vault status exits 2 when sealed (reachable but not unsealed) — that is OK here.
        echo "Waiting for Vault API to respond..."
        for i in $(seq 1 30); do
          STATUS_JSON=$(vault status -format=json 2>/dev/null || true)
          [ -n "$STATUS_JSON" ] && { echo "Vault responded"; break; }
          echo "  attempt $i/30, retrying in 10s..."
          sleep 10
        done

        INITIALIZED=$(echo "$STATUS_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['initialized'])" 2>/dev/null || echo "false")

        if [ "$INITIALIZED" = "False" ] || [ "$INITIALIZED" = "false" ]; then
          echo "Initializing Vault..."
          INIT_JSON=$(vault operator init \
            -recovery-shares=5 \
            -recovery-threshold=3 \
            -format=json)

          ROOT_TOKEN=$(echo "$INIT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['root_token'])")

          echo "Storing root token in SSM..."
          AWS_DEFAULT_REGION="${var.region}" \
          aws ssm put-parameter \
            --name "${local.ssm_token_name}" \
            --value "$ROOT_TOKEN" \
            --type SecureString \
            --overwrite

          echo "Storing recovery keys in SSM..."
          for i in 0 1 2 3 4; do
            KEY=$(echo "$INIT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['recovery_keys_b64'][$i])")
            AWS_DEFAULT_REGION="${var.region}" \
            aws ssm put-parameter \
              --name "/terragrunt-infra/vault/recovery-key-$i" \
              --value "$KEY" \
              --type SecureString \
              --overwrite
          done

          echo "Vault initialized and root token stored."
        else
          echo "Vault already initialized, skipping."
        fi
      fi
    EOF
  }

  triggers_replace = [
    var.vault_mode,
    helm_release.vault.metadata.app_version,
    helm_release.vault.version,
  ]
}

data "aws_ssm_parameter" "vault_root_token" {
  name            = local.ssm_token_name
  with_decryption = true

  depends_on = [terraform_data.vault_init]
}
