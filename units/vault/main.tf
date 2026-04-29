resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  version          = "0.32.0"
  namespace        = "vault"
  create_namespace = true

  values = [var.helm_values]
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

      echo "Waiting for Vault pods..."
      kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=vault \
        -n vault --timeout=300s

      if [ "${var.vault_mode}" = "dev" ]; then
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
        # HA mode: port-forward and run vault operator init
        kubectl port-forward svc/vault 18200:8200 -n vault &
        PF_PID=$!
        trap "kill $PF_PID 2>/dev/null || true" EXIT
        sleep 5

        export VAULT_ADDR="http://127.0.0.1:18200"

        INITIALIZED=$(vault status -format=json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['initialized'])" 2>/dev/null || echo "false")

        if [ "$INITIALIZED" = "False" ] || [ "$INITIALIZED" = "false" ]; then
          echo "Initializing Vault..."
          INIT_JSON=$(vault operator init \
            -recovery-shares=1 \
            -recovery-threshold=1 \
            -format=json)

          ROOT_TOKEN=$(echo "$INIT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['root_token'])")

          echo "Storing root token in SSM..."
          AWS_DEFAULT_REGION="${var.region}" \
          aws ssm put-parameter \
            --name "${local.ssm_token_name}" \
            --value "$ROOT_TOKEN" \
            --type SecureString \
            --overwrite

          echo "Vault initialized and root token stored."
        else
          echo "Vault already initialized, skipping."
        fi
      fi
    EOF
  }

  triggers_replace = [
    helm_release.vault.metadata.app_version,
    helm_release.vault.version,
  ]
}

data "aws_ssm_parameter" "vault_root_token" {
  name            = local.ssm_token_name
  with_decryption = true

  depends_on = [terraform_data.vault_init]
}
